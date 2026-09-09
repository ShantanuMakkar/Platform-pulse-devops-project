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
atlantis/            Local Atlantis (Docker + ngrok) config
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
| 2 | EKS cluster + IRSA | done |
| 3 | Atlantis (local, PR automation, locking) | this session |
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
# 1. Bootstrap: creates the state bucket + budget alert (local state, one-time)
cd bootstrap
terraform init
terraform apply \
  -var="state_bucket_name=tfstate-platform-pulse-<yourname>-<random4>" \
  -var="alert_email=you@example.com" \
  -var="aws_region=us-east-1"
cd ..
# Check your email and CONFIRM the SNS subscription — budget alerts won't
# deliver until you do.

# 2. Point the dev environment at that bucket, once:
cp environments/dev/backend.hcl.example environments/dev/backend.hcl
# edit backend.hcl: set bucket to the state_bucket_name output from step 1

# 3. Standard terraform commands from here on — backend.hcl means init
#    never prompts you again:
cd environments/dev
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Nothing billable of consequence yet from this phase alone; the VPC itself is
free. EKS lands in Phase 2.

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

## Phase 3 — Atlantis (local Docker + ngrok, PR automation, locking)

Atlantis replaces "run `terraform apply` from your laptop" with "open a PR,
Atlantis comments the plan, a human approves, Atlantis applies." It runs
**outside** the EKS cluster it manages (avoids the chicken-and-egg problem of
using the cluster to manage the cluster itself) — here, as a local Docker
container tunneled to GitHub via ngrok.

### 1. GitHub side — PAT, webhook, branch protection

1. **Personal access token**: GitHub → Settings → Developer settings →
   Personal access tokens → Tokens (classic) → generate with the `repo`
   scope. This is what Atlantis uses to comment on PRs and set status checks.
2. **Webhook secret**: generate one locally: `openssl rand -hex 20` — save it,
   you'll need it in two places (Atlantis's `.env` and the GitHub webhook).
3. **Webhook**: on `platform-infra` → Settings → Webhooks → Add webhook
   - Payload URL: `https://catalyst-monument-roving.ngrok-free.dev/events`
   - Content type: `application/json`
   - Secret: the value from step 2
   - Events: "Pull requests" and "Issue comments" (that second one is how
     Atlantis hears `atlantis plan` / `atlantis apply` comments)
4. **Branch protection**: Settings → Branches → add a rule for `main`
   - Require a pull request before merging, **1 required approval**
   - Dismiss stale approvals on new commits
   - Require status checks to pass: search for and add `atlantis/plan`
     (it won't appear until Atlantis has commented on at least one PR —
     come back to tick this after your first test PR)

Replace `YOUR_GITHUB_USERNAME` in `atlantis/repos.yaml`, `atlantis/.env`
(from the example below), and `CODEOWNERS` with your actual username first.

### 2. Run Atlantis locally

```bash
cd atlantis
cp .env.example .env
# edit .env: GH_USER, GH_TOKEN, GH_WEBHOOK_SECRET, GH_REPO_ALLOWLIST,
# ATLANTIS_URL (your ngrok static domain)

docker compose --env-file .env up
```

In a second terminal:

```bash
ngrok http 4141 --url=https://catalyst-monument-roving.ngrok-free.dev
```

Leave both running while you work through PRs below. Confirm the tunnel is
actually up by checking ngrok's terminal output shows `Forwarding` pointing
at `localhost:4141` — if you instead run `ngrok http 80` (a different port),
GitHub's webhook deliveries will fail silently against nothing listening
there.

**If you use AWS SSO**, the container needs credentials that don't expire
mid-session — `aws configure export-credentials --profile <name>` will print
a temporary access key/secret/session token; put those directly in `.env` as
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` instead of
relying on the mounted `~/.aws` (SSO's cached browser token doesn't refresh
from inside a container).

### 3. The demo script

1. **Open a PR** changing something small in `environments/dev` (e.g. bump
   `node_desired_size`). Atlantis autoplans and comments the diff within a
   few seconds — that's the webhook working.
2. **Comment `atlantis apply` before approving.** It's rejected: `apply_requirements: [approved, mergeable]`
   in `repos.yaml` is the thing doing that. This is the mechanic you asked
   about — no plan gets applied without a human's approval showing on GitHub.
3. **Approve the PR.** GitHub will not let you approve your own PR — this
   is a hard platform restriction, not a repo setting. If you have a second
   GitHub account or a collaborator, this is the real approval-gate demo:
   `apply_requirements: [approved, mergeable]` in `repos.yaml`, approval
   required before `atlantis apply` is accepted.

   Working solo, `apply_requirements` is set to `[mergeable]` only — you
   can still demonstrate the *mergeable* half of the gate (a failing check
   or unresolved conversation blocks apply the same way), just not the
   human-approval half. Worth knowing for the real job: this is exactly
   the setting you'd tighten back to `[approved, mergeable]` once there's
   an actual team reviewing PRs.
4. **Comment `atlantis apply`** — runs immediately now, no approval needed.
5. **Merge the PR.**

### 4. The locking demo (what you specifically asked about)

Open **two PRs** that both touch `environments/dev` (e.g. PR A bumps
`node_desired_size`, PR B bumps a tag) at the same time:

- PR A's autoplan runs first and takes a **lock on that project/workspace**.
- PR B's autoplan comment will show: *"This project is currently locked by an
  unapplied plan from pull request #A. To continue, delete the lock from
  #A or apply the plan from #A."*
- This is Atlantis preventing two applies from racing against the same
  state file — the exact failure mode a lock exists to stop.
- Merge or close PR A (or comment `atlantis unlock` on it) — PR B's lock
  clears and it can plan/apply normally.

### Cost note

Atlantis itself is free (your own laptop, your own Docker). The only cost
this phase can trigger is if a plan you apply changes billable AWS resources
— same rules as Phase 1/2...
