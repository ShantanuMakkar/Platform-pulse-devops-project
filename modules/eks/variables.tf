variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS-supported Kubernetes minor version. Check current support at https://endoflife.date/amazon-eks before relying on this default long-term."
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets for the control plane ENIs and the node group. Public-only for this POC (see modules/vpc)."
  type        = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is cheaper for a POC but can be reclaimed."
  type        = string
  default     = "SPOT"
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "admin_principal_arns" {
  description = "IAM user/role ARNs to grant EKS cluster-admin access via access entries (EKS Cluster Access Management, not the legacy aws-auth ConfigMap). Include the ARN of whoever will run kubectl/helm/argocd against this cluster — typically your own IAM user or SSO role."
  type        = list(string)
  default     = []
}
