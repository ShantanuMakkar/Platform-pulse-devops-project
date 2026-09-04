# Platform Pulse — Platform Engineering POC

A hands-on proof-of-concept covering the toolchain of a modern platform team:
**Terraform → AWS → EKS → Helm → ArgoCD → Atlantis → GitHub Actions.**

The deployed product is **Platform Pulse**, a one-page status dashboard that proves
every stage of the pipeline actually worked: the git SHA it's running, the pod/node
it landed on (Kubernetes Downward API), and a live hit counter written to DynamoDB
via IRSA (no static AWS keys anywhere in the cluster).

## Why this repo looks the way it does

- **No NAT Gateway.** Nodes sit in public subnets with locked-down security groups.
  This is a cost + simplicity tradeoff explicit to a POC — production would use
  private subnets behind a NAT. Documented, not hidden.
- **Ephemeral EKS.** The control plane costs ~$0.10/hr with no free-tier exemption.
  The workflow is: `apply` → demo → `destroy`, not "leave it running." See
  `scripts/destroy-all.sh` (added in Phase 2).
- **S3 native state locking.** Terraform 1.10+ supports `use_lockfile = true` in the
  S3 backend — no DynamoDB lock table needed. One less moving part.
- **A budget guardrail is provisioned before anything else.** Phase 0 creates an AWS
  Budget with an alert at 80% of a $5 monthly cap, so a mistake shows up in your
  inbox, not just your bill.

## Repo map (this repo = `platform-infra`)

```
bootstrap/          One-time: remote state bucket + AWS Budget alert (local state)
environments/dev/   Root module for the dev environment (S3 backend, calls modules/)
modules/vpc/        VPC, public subnets only, no NAT
modules/eks/        EKS cluster + managed node group        [Phase 2]
modules/irsa/       IAM Roles for Service Accounts           [Phase 2/6]
atlantis/            Local Atlantis (Docker + ngrok) config   [Phase 3]
scripts/             Helper + teardown scripts
```

Two sibling repos complete the project:
- **`platform-app`** — the dashboard's source + GitHub Actions CI     [Phase 4]
- **`platform-gitops`** — the Helm chart ArgoCD watches                [Phase 5/6]

## Roadmap

| Phase | What | Status |
|---|---|---|
| 0 | AWS/GitHub setup, budget alert | this session |
| 1 | Terraform backend + VPC | this session |
| 2 | EKS cluster + IRSA | next |
| 3 | Atlantis (local, PR automation, locking) | — |
| 4 | GitHub Actions CI (OIDC, build, push) | — |
| 5 | Helm chart for the app | — |
| 6 | ArgoCD (Terraform-installed, auto-sync) | — |
| 7 | End-to-end demo | — |
| 8 | Teardown + final polish | — |

## Prerequisites (Phase 0 — do these before Phase 1)

1. **AWS account** with console + programmatic access. Use an IAM identity with
   admin rights for this POC (a dedicated `platform-poc` IAM user or SSO profile —
   don't reuse root).
2. **AWS CLI** configured: `aws configure` (or an SSO profile), verify with
   `aws sts get-caller-identity`.
3. **Terraform >= 1.10** (needed for S3 native locking):
   `terraform version`
4. **A GitHub account/org** — this repo, plus `platform-app` and `platform-gitops`,
   will live there.
5. **Pick a globally-unique S3 bucket name** for Terraform state, e.g.
   `tfstate-platform-pulse-<yourname>-<random4>`. You'll need it in the next step.

## Phase 1 — bring up the backend + VPC

```bash
# 1. Bootstrap: creates the state bucket + budget alert (uses local state, one-time)
cd bootstrap
terraform init
terraform apply \
  -var="state_bucket_name=tfstate-platform-pulse-<yourname>-<random4>" \
  -var="alert_email=you@example.com" \
  -var="aws_region=us-east-1"
# Check your email and CONFIRM the SNS subscription — budget alerts won't
# deliver until you do.

# 2. Wire the dev environment to that bucket
cd ../environments/dev
terraform init \
  -backend-config="bucket=tfstate-platform-pulse-<yourname>-<random4>" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"

terraform plan
terraform apply
```

`terraform apply` in `environments/dev` stands up the VPC (2 public subnets across
2 AZs, IGW, route table — no NAT). Nothing billable of consequence yet; the VPC
itself is free. EKS lands in Phase 2.

### Tearing down Phase 1 only

```bash
cd environments/dev && terraform destroy
```

Leave `bootstrap/` (the state bucket + budget alert) up for the life of the whole
project — you'll keep using it through Phase 8.
