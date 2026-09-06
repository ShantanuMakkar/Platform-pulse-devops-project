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
modules/eks/        EKS cluster + managed node group
modules/irsa/       IAM Roles for Service Accounts (generic, reusable)
atlantis/            Local Atlantis (Docker + ngrok) config   [Phase 3]
scripts/             Helper + teardown scripts
```

Two sibling repos complete the project:
- **`platform-app`** — the dashboard's source + GitHub Actions CI     [Phase 4]
- **`platform-gitops`** — the Helm chart ArgoCD watches                [Phase 5/6]

## Roadmap

| Phase | What | Status |
|---|---|---|
| 0 | AWS/GitHub setup, budget alert | done |
| 1 | Terraform backend + VPC | done |
| 2 | EKS cluster + IRSA | this session |
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

## Phase 2 — EKS cluster + IRSA

Same `environments/dev` directory — this phase adds to the plan you already
applied, it doesn't replace it.

```bash
cd environments/dev
terraform plan   # review: EKS cluster, 1 spot node, DynamoDB table, IRSA role
terraform apply  # takes ~10-15 min — EKS control plane provisioning is slow
```

What this creates:
- **EKS cluster** (`aws_eks_cluster`), Kubernetes 1.35, public endpoint, API-based
  access management (no `aws-auth` ConfigMap editing — access is granted via
  `aws_eks_access_entry`, and the identity you `apply` with is always included
  automatically so you can't lock yourself out)
- **One spot `t3.small` managed node group** — cheapest reasonable compute; spot
  can be reclaimed, fine for a POC, not for anything you can't tolerate losing
- **OIDC provider** on the cluster, the prerequisite for IRSA
- **`modules/irsa`** — a generic, reusable "IAM role assumable only by one specific
  Kubernetes service account" module. Trust policy is scoped by namespace + SA
  name, not "any pod in the cluster"
- **DynamoDB table** (`<cluster_name>-hits`, on-demand billing) — the hit counter
  Platform Pulse will read/write
- **One IRSA role**, `app_irsa`, whose inline policy allows exactly
  `dynamodb:GetItem` / `dynamodb:UpdateItem` on exactly that one table's ARN —
  nothing broader. This is the concrete "no static AWS keys in the pod" piece.

```bash
# point kubectl at the new cluster
$(terraform output -raw configure_kubectl 2>/dev/null) || \
  aws eks update-kubeconfig --name platform-pulse-dev --region us-east-1

kubectl get nodes    # should show your one t3.small, Ready
```

### Cost reality check for this phase

The EKS control plane starts billing ($0.10/hr) the moment `apply` finishes, and
keeps billing until `destroy`. The spot node adds a few cents/hr on top. **Don't
leave this running between sessions** — see below.

### Tearing down

```bash
./scripts/destroy-all.sh
```

Destroys everything in `environments/dev` (cluster, node group, VPC, DynamoDB,
IRSA role) with a confirmation prompt. Leaves `bootstrap/` (the state bucket +
budget alert) standing — that's deliberate, keep it up for the life of the whole
project through Phase 8.

To tear down Phase 1's VPC only (before Phase 2 existed), the equivalent was
`terraform destroy` directly — now that EKS depends on the VPC, always destroy
through `environments/dev` as a whole.
