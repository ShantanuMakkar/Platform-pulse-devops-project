terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Intentionally local state here — this is the module that CREATES the
  # remote state bucket, so it can't depend on itself. Keep the resulting
  # terraform.tfstate file safe (it's the source of truth for your state
  # bucket's name); it's small and rarely changes after Phase 0.
}

provider "aws" {
  region = var.aws_region
}
