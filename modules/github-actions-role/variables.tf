variable "role_name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (created once per AWS account — see environments/dev/github-oidc.tf)."
  type        = string
}

variable "github_repo" {
  description = "In the form \"owner/repo\", e.g. \"ShantanuMakkar/platform-app\"."
  type        = string
}

variable "allowed_refs" {
  description = "Which branches/refs may assume this role, scoped via the OIDC sub claim. Default: only pushes to main — not every branch or PR."
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}

variable "inline_policy_json" {
  type    = string
  default = null
}
