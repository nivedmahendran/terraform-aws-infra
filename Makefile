.PHONY: help init fmt validate lint plan apply destroy local-up local-down local-plan clean

TF ?= terraform
ENV ?= environments/dev

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

init: ## Initialise the dev environment
	cd $(ENV) && $(TF) init

fmt: ## Format all Terraform files
	$(TF) fmt -recursive

fmt-check: ## Fail if any file is unformatted (CI gate)
	$(TF) fmt -check -recursive

validate: ## Validate every module and environment
	@for d in bootstrap environments/dev modules/network modules/security; do \
		printf "%-22s " "$$d"; \
		(cd $$d && $(TF) init -backend=false -input=false > /dev/null 2>&1 && \
		 $(TF) validate -no-color > /dev/null 2>&1 && echo "VALID" || echo "FAIL"); \
	done

lint: ## Run tflint across the repo
	tflint --init && tflint --recursive

plan: ## Plan the dev environment
	cd $(ENV) && $(TF) plan

apply: ## Apply the dev environment
	cd $(ENV) && $(TF) apply

destroy: ## Destroy the dev environment
	cd $(ENV) && $(TF) destroy

local-up: ## Start LocalStack
	docker compose up -d localstack

local-down: ## Stop LocalStack
	docker compose down

local-plan: ## Plan against LocalStack (no AWS account needed)
	docker compose run --rm terraform \
		-c "cd environments/dev && terraform init -input=false && terraform plan -input=false"

clean: ## Remove local Terraform caches
	find . -name '.terraform' -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name '.terraform.lock.hcl' -delete
	echo "cleaned"
