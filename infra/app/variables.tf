variable "project" {
  type    = string
  default = "orders-api"
}

variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "allowed_cidrs" {
  description = "可以連到 ALB 的來源 IP（內部服務：填公司/自己的出口 IP，例如 [\"1.2.3.4/32\"]）"
  type        = list(string)
}

variable "image_tag" {
  description = "首次建立時使用的映像 tag（之後由 CI 更新，Terraform 不再管）"
  type        = string
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "alert_email" {
  description = "CloudWatch Alarm 通知對象（SNS email，需到信箱點確認訂閱）"
  type        = string
}

variable "alarm_5xx_threshold" {
  description = "每分鐘 5xx 次數門檻"
  type        = number
  default     = 5
}

variable "log_retention_days" {
  type    = number
  default = 7
}
