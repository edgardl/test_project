variable "github_token" {
  type        = string
  description = "Personal access token for GHCR"
  sensitive   = true # This hides it from logs
}

variable "github_user" {
  type        = string
  description = "GitHub username"
}

variable "github_repo_name" {
  type        = string
  default     = "perl-testing"
}

variable "db_feedback_table" {
  type        = string
  default     = "ddg_feedback"
}
