output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

# ---- oidc 模式 ----
output "github_deploy_role_arn" {
  description = "oidc 模式：填到 GitHub secret AWS_DEPLOY_ROLE_ARN，並設 repo variable AWS_AUTH_MODE=oidc"
  value       = try(aws_iam_role.github_deploy[0].arn, null)
}

# ---- access_key 模式 ----
output "ci_access_key_id" {
  description = "access_key 模式：填到 GitHub secret AWS_ACCESS_KEY_ID"
  value       = try(aws_iam_access_key.ci[0].id, null)
}

output "ci_secret_access_key" {
  description = "access_key 模式：填到 GitHub secret AWS_SECRET_ACCESS_KEY（用 terraform output -raw 取出，勿貼到任何文件）"
  value       = try(aws_iam_access_key.ci[0].secret, null)
  sensitive   = true
}

output "backend_hcl" {
  description = "app layer 的 backend 設定，寫到 infra/app/backend.hcl（已被 .gitignore 排除）"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.tfstate.bucket}"
    key          = "app/terraform.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
