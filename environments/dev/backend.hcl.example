# Copy this file to backend.hcl (gitignored) and fill in your real bucket
# name from bootstrap's `terraform output state_bucket_name`.
#
#   cp backend.hcl.example backend.hcl
#
# Then always init with:
#   terraform init -backend-config=backend.hcl

bucket       = "tfstate-platform-pulse"
key          = "dev/terraform.tfstate"
region       = "us-east-1"
use_lockfile = true
