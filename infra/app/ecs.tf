resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
  setting {
    name  = "containerInsights"
    value = "disabled" # 會產生額外 custom metrics 費用；改用 ALB 內建指標判斷服務健康
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256 # 0.25 vCPU：Fargate 最小規格
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64" # Apple Silicon 本機 build 要加 --platform linux/amd64
  }

  container_definitions = jsonencode([{
    name                   = "app"
    image                  = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential              = true
    readonlyRootFilesystem = true
    portMappings           = [{ containerPort = 8000, protocol = "tcp" }]
    environment            = [{ name = "APP_VERSION", value = var.image_tag }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name                              = "${var.project}-svc"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 30

  # 滾動更新：先起新的、健康後才關舊的 → 部署期間不中斷
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # 新版本起不來（健康檢查一直失敗）→ 自動回滾到上一版
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8000
  }

  # 責任切分：Terraform 管「基礎設施」，CI 管「跑哪個版本」。
  # CI 每次部署會註冊新的 task definition revision，若不忽略，下次 terraform plan 會想改回去。
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http]
}
