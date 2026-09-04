variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in resource naming and tags."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name (created in Phase 2; referenced by VPC tags now)."
  type        = string
  default     = "platform-pulse-dev"
}
