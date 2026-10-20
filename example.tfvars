# Example variable file. Copy to terraform.tfvars and fill in.
#
# terraform.tfvars is gitignored — never commit real credentials.
#
# For real AWS, credentials normally come from the environment or an AWS
# profile rather than from this file:
#   export AWS_PROFILE=my-profile
#
# The values below are for LocalStack, where any non-empty key works.

region = "eu-west-1"
name   = "portfolio"

# Only needed if you want a different VPC range.
# vpc_cidr = "10.10.0.0/16"
