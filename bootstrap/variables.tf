variable "aws_region" {
  description = "AWS region for the state bucket and budget."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state."
  type        = string
}

variable "alert_email" {
  description = "Email address for AWS Budget threshold alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly cost cap in USD. An alert fires at 80% of this."
  type        = number
  default     = 5
}

variable "aws_profile" {
  description = "Optional named AWS CLI/SSO profile. Leave unset to use the default credential chain (env vars, default profile, SSO session already logged in)."
  type        = string
  default     = null
}
