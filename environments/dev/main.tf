data "aws_caller_identity" "current" {}

locals {
  # Always include whoever is running Terraform, plus anything explicitly
  # passed in — so you never lock yourself out of kubectl access.
  admin_principal_arns = distinct(concat(
    [data.aws_caller_identity.current.arn],
    var.admin_principal_arns
  ))
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = "platform-pulse-${var.environment}"
  cluster_name = var.cluster_name
}

module "eks" {
  source = "../../modules/eks"

  cluster_name          = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.public_subnet_ids
  admin_principal_arns   = local.admin_principal_arns
}

# --- App data store: the hit counter Platform Pulse reads/writes ---------

resource "aws_dynamodb_table" "hits" {
  name         = "${var.cluster_name}-hits"
  billing_mode = "PAY_PER_REQUEST" # no capacity to size/pay for at rest
  hash_key     = "counter_id"

  attribute {
    name = "counter_id"
    type = "S"
  }
}

# IRSA role for the app: scoped to exactly this one table, exactly these
# actions — not a broad DynamoDBFullAccess managed policy. This is the
# role the Helm chart (Phase 5) annotates onto the app's service account.
module "app_irsa" {
  source = "../../modules/irsa"

  role_name             = "${var.cluster_name}-app-irsa" 
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_issuer_url        = module.eks.oidc_issuer_url
  namespace              = "platform-pulse"
  service_account_name   = "platform-pulse"

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
      ]
      Resource = aws_dynamodb_table.hits.arn
    }]
  })
}


# --- CI: GitHub Actions can push to ECR, nothing more --------------------
# Scoped to platform-app's main branch only (see modules/github-actions-role).

module "github_actions_ecr_push" {
  source = "../../modules/github-actions-role"

  role_name         = "${var.cluster_name}-gha-ecr-push"
  oidc_provider_arn = aws_iam_openid_connect_provider.github_actions.arn
  github_repo       = "ShantanuMakkar/Platform-pulse-app-project"

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage",
        ]
        Resource = aws_ecr_repository.platform_pulse.arn
      },
    ]
  })
}