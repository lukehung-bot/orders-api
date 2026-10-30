variable "project" {
  description = "專案名稱，所有資源名稱的前綴"
  type        = string
  default     = "orders-api"
}

variable "region" {
  description = "AWS region（新版免費方案帳號只能在專案指定的區域建立運算資源）"
  type        = string
  default     = "ap-southeast-2"
}

variable "alert_email" {
  description = "接收預算告警的 email"
  type        = string
}

variable "monthly_budget_usd" {
  description = "每月預算上限（USD）"
  type        = string
  default     = "10"
}

variable "github_repo" {
  description = "允許部署的 GitHub repo，格式 owner/name"
  type        = string
}

variable "ci_auth_mode" {
  description = "CI 取得 AWS 憑證的方式：access_key（免費方案帳號）或 oidc（一般帳號 / 付費方案，較佳）"
  type        = string
  default     = "access_key"
  validation {
    condition     = contains(["access_key", "oidc"], var.ci_auth_mode)
    error_message = "ci_auth_mode 只能是 access_key 或 oidc。"
  }
}
