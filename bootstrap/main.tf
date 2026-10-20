# Remote state backend bootstrap.
#
# This root module creates the S3 bucket and DynamoDB table that every other
# module uses as its backend. It is deliberately a separate root module: the
# backend that stores state cannot itself rely on that backend, and this is the
# classic chicken-and-egg problem in Terraform.
#
# Run this ONCE, with local state, before applying anything in ../environments.
#
#   cd bootstrap
#   terraform init
#   terraform apply -var="bucket_name=my-tfstate-bucket"
#
# Then copy the outputs into environments/dev/backend.tf.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are globally unique; default to account id to avoid collisions.
  bucket_name = var.bucket_name != "" ? var.bucket_name : "tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Prevent an accidental `terraform destroy` from deleting the state bucket.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = local.bucket_name
    ManagedBy = "terraform"
    Purpose   = "terraform-remote-state"
  }
}

# Versioning is the safety net: a bad apply can be rolled back by restoring a
# previous state object version instead of hand-editing state.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State files describe your whole infrastructure, so they must not be readable
# by anyone outside the account.
resource "aws_s3_bucket_policy" "deny_insecure_transport" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# DynamoDB provides the state lock. Without it two concurrent applies can
# corrupt the same state file.
resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name      = var.lock_table_name
    ManagedBy = "terraform"
    Purpose   = "terraform-state-lock"
  }
}
