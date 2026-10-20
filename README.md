# terraform-aws-infra

[![Terraform CI](https://github.com/nivedmahendran/terraform-aws-infra/actions/workflows/terraform.yml/badge.svg)](https://github.com/nivedmahendran/terraform-aws-infra/actions/workflows/terraform.yml)
[![Terraform](https://img.shields.io/badge/Terraform-v1.5+-7B42BC?logo=terraform)](https://www.terraform.io)
[![AWS Provider](https://img.shields.io/badge/AWS%20Provider-v6-FF9900?logo=amazonaws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Modular, reusable AWS infrastructure described entirely in Terraform — VPC
network, security groups, S3 storage, and IAM, with **remote state and locking
bootstrapped by Terraform itself**.

## Why this exists

Most Terraform repos assume the state bucket already exists and never explain
how it was created. This project closes that gap: the `bootstrap/` module
creates the S3 bucket and DynamoDB lock table, and every environment then uses
them as a backend. That is the pattern you need for team use — two engineers
running `apply` at the same time should never be able to corrupt state.

## Architecture

```
bootstrap/                     creates the state bucket + lock table (local state)
  └── aws_s3_bucket            versioned, KMS-encrypted, public access blocked
  └── aws_dynamodb_table       LockID hash key, point-in-time recovery
  └── aws_s3_bucket_policy     denies non-TLS requests
          │
          ▼  outputs feed backend.tf
environments/dev/              uses the remote backend
  └── module "network"         VPC, public/private subnets, IGW, NAT, routing
  └── module "security"        LB + app security groups, SG-to-SG references
  └── aws_s3_bucket "app"      artifact bucket, versioned, lifecycle-expired
  └── aws_iam_role / policy    least-privilege S3 access for workloads
          │
          ▼  consumed by
modules/network/               generic, reusable, no environment opinions
modules/security/              generic, reusable
```

## Layout

```
terraform-aws-infra/
├── bootstrap/                 # one-time: creates remote state backend
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── environments/
│   └── dev/                   # composes the modules for the dev environment
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── modules/                   # reusable modules — no environment specifics
│   ├── network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── security/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── .github/workflows/terraform.yml
├── docker-compose.yml         # LocalStack for local plan/apply testing
├── trivy.yaml
├── .trivyignore               # accepted findings, with reasoning
└── .gitignore
```

## Design decisions

**Remote state with locking.** State is stored in S3 with versioning enabled and
KMS encryption, and locked via DynamoDB. Versioning is the safety net — a bad
apply can be rolled back by restoring a previous object version rather than
hand-editing state.

**Modules have no environment opinions.** `modules/network` takes a CIDR and an
AZ count; it does not know it is "dev". Environments pass the values. This is
what makes the module reusable across environments.

**Subnets are derived, not hardcoded.** `cidrsubnet()` carves subnets from the
VPC CIDR, so changing `var.vpc_cidr` or `var.az_count` never produces
overlapping ranges.

**Security groups reference each other, not CIDRs.** The app security group
accepts traffic from the load balancer's security group rather than from
`0.0.0.0/0`. Only traffic that actually traversed the LB is allowed through.

**Single NAT gateway by default.** One NAT saves ~$32/month per additional AZ.
`var.single_nat_gateway = false` gives one per AZ for production resilience —
a deliberate cost/availability trade-off, documented rather than hidden.

## Usage

### 1. Bootstrap the state backend (once)

```bash
cd bootstrap
terraform init
terraform apply -var="bucket_name=my-unique-tfstate-bucket"
```

Copy the `backend_config` output into `environments/dev/main.tf` and uncomment
the `backend "s3"` block.

### 2. Apply the environment

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

## Local testing without an AWS account

The repo ships a LocalStack setup so the configuration can be planned and
applied locally:

```bash
docker compose up -d localstack

docker compose run --rm terraform \
  -c "cd environments/dev && terraform init && terraform plan"

docker compose down
```

Terraform talks to LocalStack via `AWS_ENDPOINT_URL`, so the same code runs
against either without changes.

**Known LocalStack limitation.** `terraform plan` against LocalStack is clean
(31 resources, exit 0). A full `terraform apply` creates everything except the
final tag-read on the S3 bucket, which fails because the AWS provider v6 reads
account-level bucket tags through the S3 **Control** API and addresses it as
`https://<account-id>.<endpoint>`. LocalStack does not resolve that host form:

```
dial tcp: lookup 000000000000.127.0.0.1: no such host
```

This is an emulator limitation, not a configuration bug — the same apply works
against real AWS. Use `plan` locally to prove the configuration, and `apply`
against a real (or ephemeral) AWS account.

## CI

Every push runs:

1. **`terraform fmt -check`** — formatting gate
2. **`terraform validate`** — every module and environment, `-backend=false`
3. **Trivy** — misconfiguration scan, fails on HIGH/CRITICAL
4. **tflint** — provider and style linting

### On the one accepted Trivy finding

Scanning is only worth having if the output is believed. `AWS-0104`
(unrestricted egress) fires on the application group's HTTPS and HTTP rules:
the check keys on the CIDR, not the port, so any rule that reaches package
mirrors and AWS APIs without a NAT gateway trips it.

Every other finding from that rule was fixed in code rather than suppressed:

| Finding | Resolution |
|---|---|
| Unrestricted egress on the LB group | Scoped to the app security group — the LB has nowhere else to reach |
| DNS egress to `0.0.0.0/0` | Scoped to the VPC resolver, `cidrhost(vpc_cidr, 2)/32` |
| Subnets auto-assigning public IPs | Set `map_public_ip_on_launch = false` |
| Buckets encrypted with the AWS-managed key | Customer-managed KMS keys with rotation |

The two remaining rules are accepted explicitly in `.trivyignore`, which
records the alternatives considered and the NAT-plus-endpoints design that
would remove them. That file is a decision log, not a mute button.

## Requirements

| Tool | Version |
|---|---|
| Terraform | >= 1.5 |
| AWS provider | ~> 6.0 |
| Docker (local testing) | any recent |

## Notes

- No credentials or `*.tfvars` are committed; `.gitignore` covers both.
- `bootstrap/` intentionally keeps **local** state — the backend cannot store
  its own state on first creation.
- NAT gateways and EIPs are the main recurring cost. Destroy the environment
  when you are done experimenting.

## License

MIT — see [LICENSE](LICENSE).
