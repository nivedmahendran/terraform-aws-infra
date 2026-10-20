output "bucket_name" {
  description = "S3 bucket holding Terraform state"
  value       = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  description = "DynamoDB table used for state locking"
  value       = aws_dynamodb_table.lock.name
}

output "backend_config" {
  description = "Paste this into environments/*/backend.tf"
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.state.bucket}"
    dynamodb_table = "${aws_dynamodb_table.lock.name}"
  EOT
}
