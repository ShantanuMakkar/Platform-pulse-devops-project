terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Partial configuration on purpose — backend values can't reference
  # variables, so bucket/key/region/use_lockfile are supplied at `init`
  # time via -backend-config flags (see README.md Phase 1, or
  # scripts/init-backend.sh). This is standard practice for a backend
  # whose bucket name is only known once, not hardcoded per environment.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "platform-pulse"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
