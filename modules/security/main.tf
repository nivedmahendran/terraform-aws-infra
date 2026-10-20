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

# The load balancer must reach application instances. This egress rule is
# scoped to the app security group rather than 0.0.0.0/0: the LB has no reason
# to initiate connections anywhere else. "Allow all outbound" is the common
# default and it is a finding for good reason — see AWS-0104.
resource "aws_vpc_security_group_egress_rule" "lb_to_app" {
  security_group_id            = aws_security_group.lb.id
  description                  = "Reach application instances on the app port"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
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

# App instances need outbound to pull packages and call AWS APIs. HTTPS and
# HTTP are the only destinations that serves, so egress is scoped to those
# ports rather than "all protocols".
#
# These two rules necessarily use 0.0.0.0/0 because package mirrors and AWS
# API endpoints have no stable CIDR set to allow-list. Trivy's AVD-AWS-0104
# fires on the CIDR regardless of port; the reasoning for accepting it, and
# the NAT-plus-endpoints design that would remove it, are recorded in
# trivy.yaml. Everything else that check flagged has been fixed in code.
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs, package mirrors, and registries"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP for repository metadata (many mirrors are not TLS-only)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# DNS is the one destination we can scope precisely: the VPC resolver is always
# at the base of the VPC CIDR (VPC_CIDR + 2). Restricting this to the VPC
# removes an unrestricted-egress finding for real, rather than suppressing it.
resource "aws_vpc_security_group_egress_rule" "app_dns_udp" {
  security_group_id = aws_security_group.app.id
  description       = "DNS to the VPC resolver only"
  cidr_ipv4         = "${cidrhost(var.vpc_cidr, 2)}/32"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}

resource "aws_vpc_security_group_egress_rule" "app_dns_tcp" {
  security_group_id = aws_security_group.app.id
  description       = "DNS over TCP to the VPC resolver (large responses and zone transfers)"
  cidr_ipv4         = "${cidrhost(var.vpc_cidr, 2)}/32"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
}
