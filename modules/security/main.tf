# Baseline security groups.
#
# One group for the load balancer (public ingress) and one for application
# workloads (traffic only from the load balancer). Keeping them separate means
# a compromise of an app instance exposes no inbound surface.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_security_group" "lb" {
  name        = "${var.name}-lb"
  description = "Ingress for the public load balancer"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-lb" })
}

# HTTP/HTTPS are open to the internet on purpose: this is the public entry point.
resource "aws_vpc_security_group_ingress_rule" "lb_http" {
  security_group_id = aws_security_group.lb.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "lb_https" {
  security_group_id = aws_security_group.lb.id
  description       = "HTTPS from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "lb_all" {
  security_group_id = aws_security_group.lb.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Application instances; ingress from the load balancer only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-app" })
}

# Referencing the LB security group (not a CIDR) means only traffic that
# actually came through the load balancer is accepted.
resource "aws_vpc_security_group_ingress_rule" "app_from_lb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from the load balancer"
  referenced_security_group_id = aws_security_group.lb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Allow all outbound (package installs, AWS APIs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
