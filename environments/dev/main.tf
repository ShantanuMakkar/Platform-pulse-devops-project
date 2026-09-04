module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = "platform-pulse-${var.environment}"
  cluster_name = var.cluster_name
}

# modules/eks and modules/irsa are called from here starting Phase 2.
