variable "name" {
  description = "Name prefix applied to every resource"
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to"
  type        = string
}

variable "app_port" {
  description = "Port the application listens on"
  type        = number
  default     = 8080
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
