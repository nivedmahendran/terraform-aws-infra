variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "name" {
  description = "Project name used as a resource prefix"
  type        = string
  default     = "portfolio"
}

variable "vpc_cidr" {
  description = "CIDR block for the environment VPC"
  type        = string
  default     = "10.10.0.0/16"
}
