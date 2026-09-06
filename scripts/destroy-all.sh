#!/usr/bin/env bash
# Tears down everything billable: environments/dev (EKS, node group, VPC,
# DynamoDB, IRSA role). Leaves bootstrap/ (state bucket + budget) standing —
# rerun apply from environments/dev any time to bring the demo back up.
set -euo pipefail

cd "$(dirname "$0")/../environments/dev"
echo "About to destroy the dev environment (EKS cluster + node group + VPC + DynamoDB)."
read -p "Type 'destroy' to confirm: " confirm
if [ "$confirm" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

terraform destroy
echo "Done. bootstrap/ (state bucket + budget alert) is still up — that's expected."
