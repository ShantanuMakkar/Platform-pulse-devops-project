output "state_bucket_name" {
  description = "Pass this to `terraform init -backend-config=bucket=...` in environments/dev."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_region" {
  value = var.aws_region
}
