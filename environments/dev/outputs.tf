output "vpc_id" {
  description = "VPC ID for the dev environment"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.network.private_subnet_ids
}

output "app_bucket" {
  description = "Name of the application artifact bucket"
  value       = aws_s3_bucket.app.bucket
}

output "app_instance_profile" {
  description = "Instance profile name for application instances"
  value       = aws_iam_instance_profile.app.name
}

output "app_security_group_id" {
  description = "Security group for application instances"
  value       = module.security.app_security_group_id
}
