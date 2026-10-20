variable "name" {
  description = "Name prefix applied to every resource"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 so subnets span more than one zone."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ (cheaper, less resilient)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
