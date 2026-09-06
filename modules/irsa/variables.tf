variable "role_name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "From modules/eks output oidc_provider_arn."
  type        = string
}

variable "oidc_issuer_url" {
  description = "From modules/eks output oidc_issuer_url (no https:// prefix)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account that will assume this role."
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name. The pod must set this exact serviceAccountName, and the SA must carry the eks.amazonaws.com/role-arn annotation with this role's ARN."
  type        = string
}

variable "policy_arns" {
  description = "Managed policy ARNs to attach. Prefer inline_policy_json for anything scoped to a single resource (e.g. one DynamoDB table) instead of a broad managed policy."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Optional inline IAM policy JSON, for least-privilege single-resource grants."
  type        = string
  default     = null
}
