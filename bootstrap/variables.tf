variable "region" {
  description = "AWS region for the state bucket and lock table"
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name. Leave empty to derive from the AWS account id."
  type        = string
  default     = ""
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking"
  type        = string
  default     = "terraform-locks"
}
