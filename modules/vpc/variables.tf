variable "name_prefix" {
  description = "Prefix applied to all resource Name tags."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. Used only for the kubernetes.io discovery tags — the cluster itself is created in Phase 2."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ."
  type        = list(string)
  default     = ["10.20.0.0/20", "10.20.16.0/20"]
}
