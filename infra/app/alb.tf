resource "aws_lb" "main" {
  name                       = "${var.project}-alb"
  load_balancer_type         = "application"
  internal                   = false # 練習需從自己電腦截圖；以 allowed_cidrs 限制來源。正式內部服務應改 internal + VPN
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.project}-tg"
  port                 = 8000
  protocol             = "HTTP"
  target_type          = "ip" # Fargate awsvpc 模式必須用 ip
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30 # 預設 300 秒，縮短讓部署更快完成

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# 沒有網域與憑證，先用 HTTP。正式環境：ACM 憑證 + 443 listener，80 轉 301
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
