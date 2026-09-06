output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this to set up kubectl access."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.hits.name
}

output "app_irsa_role_arn" {
  description = "Annotate the app's Kubernetes service account with eks.amazonaws.com/role-arn = this value (done for you by the Helm chart in Phase 5)."
  value       = module.app_irsa.role_arn
}
