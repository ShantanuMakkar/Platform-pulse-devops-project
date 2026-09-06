variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional named AWS CLI/SSO profile. Leave unset to use the default credential chain."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name, used in resource naming and tags."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "platform-pulse-dev"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "admin_principal_arns" {
  description = "IAM principal ARNs (your user/SSO role) to grant EKS cluster-admin. If left empty, the identity running `terraform apply` is added automatically."
  type        = list(string)
  default     = []
}
