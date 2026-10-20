# Development environment.
#
# Composes the network and security modules, then adds an S3 bucket and the
# IAM policy that grants scoped access to it. This is the shape a real project
# would use: modules stay generic, environments decide the parameters.

terraform {
  required_version = ">= 1.5"

  # Backend values come from bootstrap/ output. They are commented out so that
  # `terraform init` works locally before the bucket exists. Uncomment after
  # running the bootstrap module.
  #
  # backend "s3" {
  #   bucket         = "tfstate-123456789012"
  #   key            = "dev/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "network" {
  source = "../../modules/network"

  name               = "${var.name}-dev"
  vpc_cidr           = var.vpc_cidr
  az_count           = 2
  single_nat_gateway = true
  tags               = local.common_tags
}

module "security" {
  source = "../../modules/security"

  name     = "${var.name}-dev"
  vpc_id   = module.network.vpc_id
  vpc_cidr = module.network.vpc_cidr
  app_port = 8080
  tags     = local.common_tags
}

# Application artifact bucket. Private by default, encrypted, versioned.
resource "aws_s3_bucket" "app" {
  bucket = "${var.name}-dev-app-${data.aws_caller_identity.current.account_id}"
}

# Customer-managed rather than SSE-S3: artifacts are decryptable by anyone with
# s3:GetObject under SSE-S3, whereas a CMK lets the key policy restrict who can
# read the data even if they hold the object permission.
resource "aws_kms_key" "app" {
  description             = "Encrypts application artifacts"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "app" {
  name          = "alias/${var.name}-dev-app"
  target_key_id = aws_kms_key.app.key_id
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.app.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule keeps storage cost from growing without bound in a dev account.
resource "aws_s3_bucket_lifecycle_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {
      prefix = "artifacts/"
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

data "aws_caller_identity" "current" {}

# Least-privilege policy for workloads that read and write the artifact bucket.
resource "aws_iam_policy" "app_s3" {
  name        = "${var.name}-dev-app-s3"
  description = "Scoped access to the ${var.name} dev artifact bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = aws_s3_bucket.app.arn
      },
      {
        Sid    = "ReadWriteObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.app.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role" "app" {
  name = "${var.name}-dev-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_s3" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_s3.arn
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-dev-app"
  role = aws_iam_role.app.name
}
