# ---------------------------------------------------------------------------
# Bootstrap layer：帳號層級、生命週期比服務長的資源
#   - 預算告警（作答原則：開始前先設定）
#   - Terraform remote state 用的 S3 bucket
#   - ECR repository（映像要先存在，ECS service 才拉得到 → 解決雞生蛋問題）
#   - GitHub Actions OIDC provider + 部署用 IAM role（CI 不需要長期金鑰）
# 這一層本身的 state 存在本機（它負責建立 state bucket，無法自己存自己）
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Layer     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------- 1. 預算告警 ----------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [
      { type = "ACTUAL", pct = 50 },
      { type = "ACTUAL", pct = 80 },
      { type = "ACTUAL", pct = 100 },
      { type = "FORECASTED", pct = 100 },
    ]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.pct
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = [var.alert_email]
    }
  }
}

# ---------------- 2. Terraform state bucket ----------------
resource "aws_s3_bucket" "tfstate" {
  # bucket 名稱含帳號 ID 以確保全域唯一；名稱只出現在本機產生的 backend.hcl，不進 repo
  bucket        = "${var.project}-tfstate-${local.account_id}"
  force_destroy = true # 練習用：destroy 時連同 state 版本一起刪除
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------- 3. ECR ----------------
resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "IMMUTABLE" # 同一個 tag 不能被覆蓋 → 每個 git SHA 對應唯一映像，回滾可追溯
  force_delete         = true        # 練習用：destroy 時連映像一起刪

  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "只保留最近 10 個映像，控制儲存費用"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

# ---------------- 4. CI 身分（兩種模式擇一） ----------------
# ci_auth_mode = "access_key"（預設）：新版免費方案帳號的 SCP 擋掉 iam:*Provider*，
#   無法建立 OIDC provider，改用「最小權限的 CI 專用 IAM user + access key 放 GitHub Secrets」。
# ci_auth_mode = "oidc"：一般帳號 / 付費方案的較佳做法 —— 無長期金鑰，只有指定 repo 的 main 分支能取得 1 小時短期憑證。
locals {
  use_oidc = var.ci_auth_mode == "oidc"
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = local.use_oidc ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS 已改用受信任 CA 驗證 GitHub OIDC，thumbprint 不再需要手動維護
}

data "aws_iam_policy_document" "github_trust" {
  count = local.use_oidc ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # 只有「指定 repo 的 main 分支」能換到這個 role；fork、其他分支、PR 都不行
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count                = local.use_oidc ? 1 : 0
  name                 = "${var.project}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_trust[0].json
  max_session_duration = 3600
}

# access_key 模式：CI 專用 IAM user（不能登入 Console，只給程式使用）
resource "aws_iam_user" "ci" {
  count = local.use_oidc ? 0 : 1
  name  = "${var.project}-github-ci"
}

# 取捨：secret 會存在 bootstrap 的 state（本機、不進 repo）。
# 降低風險：權限最小化、練習結束 terraform destroy 即刪除金鑰；正式環境應改 OIDC 或定期輪替。
resource "aws_iam_access_key" "ci" {
  count = local.use_oidc ? 0 : 1
  user  = aws_iam_user.ci[0].name
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"] # 此 API 不支援資源層級限制
    resources = ["*"]
  }
  statement {
    sid = "EcrPushThisRepoOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
  statement {
    sid       = "EcsTaskDefinition"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"] # 不支援資源層級限制
    resources = ["*"]
  }
  statement {
    sid     = "EcsUpdateThisServiceOnly"
    actions = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [
      "arn:aws:ecs:${var.region}:${local.account_id}:service/${var.project}-cluster/${var.project}-svc",
    ]
  }
  statement {
    sid       = "PassOnlyProjectTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.project}-ecs-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# 同一份最小權限 policy，依模式掛在 role（OIDC）或 user（access key）上
resource "aws_iam_role_policy" "github_deploy" {
  count  = local.use_oidc ? 1 : 0
  name   = "deploy"
  role   = aws_iam_role.github_deploy[0].id
  policy = data.aws_iam_policy_document.github_deploy.json
}

resource "aws_iam_user_policy" "ci" {
  count  = local.use_oidc ? 0 : 1
  name   = "deploy"
  user   = aws_iam_user.ci[0].name
  policy = data.aws_iam_policy_document.github_deploy.json
}
