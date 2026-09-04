# --- Remote state bucket -----------------------------------------------
# Terraform >= 1.10 supports native S3 state locking (use_lockfile = true
# on the backend block in environments/dev), so no DynamoDB lock table is
# needed here — just the bucket itself.

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Prevents an accidental `terraform destroy` in this bootstrap module
  # from deleting your only copy of remote state. Remove this line
  # deliberately in Phase 8 if you want to tear down everything, including
  # the backend itself.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Cost guardrail -------------------------------------------------------
# Fires at 80% actual spend and again at 100% forecasted spend, so you get
# warned before a surprise, not after.

resource "aws_budgets_budget" "poc_cap" {
  name         = "platform-pulse-poc-cap"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
