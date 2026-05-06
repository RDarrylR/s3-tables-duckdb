SHELL := /bin/bash
# .ONESHELL: would let recipe lines share a shell, but it requires GNU Make
# 3.82+ and macOS still ships 3.81. Recipes that need to share a variable
# between commands chain them with `&&` instead.

# AWS_PROFILE: prefer the caller's environment. If unset, read aws_profile
# from infrastructure/terraform.tfvars so terraform and the AWS CLI agree.
# Falls back to the AWS CLI default ("default") if neither is set.
TFVARS_PROFILE := $(shell awk -F'"' '/^[[:space:]]*aws_profile[[:space:]]*=/{print $$2}' infrastructure/terraform.tfvars 2>/dev/null)
AWS_PROFILE    ?= $(if $(TFVARS_PROFILE),$(TFVARS_PROFILE),default)
AWS_REGION     ?= us-east-1
TF_DIR      := infrastructure
LAYER_DIR   := ingester/layer
LAYER_ZIP   := ingester/dist/ingester-deps.zip
FUNC_ZIP    := ingester/dist/ingester.zip
PY          := python3.13

# Default ingest sizing. Override on the command line:
#   make ingest STATIONS=5000 DAYS=365
STATIONS ?= 500
DAYS     ?= 30

export AWS_PROFILE
export AWS_REGION

.PHONY: help
help:
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-22s %s\n", $$1, $$2}'

.PHONY: init
init: ## install python deps and terraform providers
	uv sync
	cd $(TF_DIR) && terraform init -upgrade

.PHONY: fmt
fmt: ## format python and terraform
	uv run ruff format ingester scripts
	uv run ruff check --fix ingester scripts
	cd $(TF_DIR) && terraform fmt -recursive

.PHONY: lint
lint: ## lint python and terraform
	uv run ruff check ingester scripts
	uv run mypy ingester/src
	cd $(TF_DIR) && terraform fmt -check -recursive
	cd $(TF_DIR) && terraform validate

.PHONY: test
test: ## run unit tests
	uv run pytest

.PHONY: layer
layer: $(LAYER_ZIP) ## build the pyiceberg + pyarrow lambda layer (arm64)

$(LAYER_ZIP): pyproject.toml uv.lock
	rm -rf $(LAYER_DIR)/python
	mkdir -p $(LAYER_DIR)/python ingester/dist
	uv export --no-hashes --no-dev --frozen --no-emit-project --format requirements.txt \
		> /tmp/layer-requirements.txt
	uv pip install \
		--target $(LAYER_DIR)/python \
		--python-platform aarch64-manylinux_2_28 \
		--python-version 3.13 \
		--only-binary=:all: \
		--requirements /tmp/layer-requirements.txt
	# Trim to stay under Lambda's 250 MB unzipped layer ceiling.
	#  - boto3 / botocore / s3transfer / jmespath ship in the Lambda Python runtime.
	#  - pyarrow Flight isn't used; its .so + lib are independent.
	#  - pyarrow C++ headers (include/) and tile-test data are safe to drop.
	#  - DON'T remove libarrow_substrait.so* - pyarrow imports _substrait at module
	#    init even when nothing in the table flow uses it.
	rm -rf $(LAYER_DIR)/python/boto3 $(LAYER_DIR)/python/boto3-*.dist-info
	rm -rf $(LAYER_DIR)/python/botocore $(LAYER_DIR)/python/botocore-*.dist-info
	rm -rf $(LAYER_DIR)/python/s3transfer $(LAYER_DIR)/python/s3transfer-*.dist-info
	rm -rf $(LAYER_DIR)/python/jmespath $(LAYER_DIR)/python/jmespath-*.dist-info
	rm -f  $(LAYER_DIR)/python/pyarrow/libarrow_flight.so* \
	       $(LAYER_DIR)/python/pyarrow/_flight*.so
	rm -rf $(LAYER_DIR)/python/pyarrow/include
	rm -rf $(LAYER_DIR)/python/pyarrow/tests
	# Don't drop pygments / rich - pyiceberg lazy-imports rich for schema-error
	# rendering, and removing it turns a useful traceback into "ModuleNotFoundError".
	find $(LAYER_DIR)/python -name '__pycache__' -type d -exec rm -rf {} +
	find $(LAYER_DIR)/python -name '*.pyc' -delete
	find $(LAYER_DIR)/python -name 'tests' -type d -exec rm -rf {} +
	find $(LAYER_DIR)/python -name 'test_*.py' -delete
	find $(LAYER_DIR)/python -name '*.pyi' -delete
	find $(LAYER_DIR)/python -name '*.dist-info' -type d -prune -exec sh -c 'rm -rf "$$1"/RECORD "$$1"/WHEEL "$$1"/INSTALLER' _ {} \;
	@du -sh $(LAYER_DIR)/python | awk '{print "  layer unzipped size: " $$1}'
	cd $(LAYER_DIR) && zip -qr ../dist/ingester-deps.zip python

.PHONY: package
package: $(FUNC_ZIP) ## package the lambda function code zip

$(FUNC_ZIP): $(wildcard ingester/src/*.py)
	mkdir -p ingester/dist
	cd ingester/src && zip -qr ../../$(FUNC_ZIP) .

.PHONY: plan
plan: layer package ## terraform plan
	cd $(TF_DIR) && terraform plan

.PHONY: apply
apply: layer package ## terraform apply
	cd $(TF_DIR) && terraform apply

.PHONY: deploy
deploy: apply ## alias for apply

.PHONY: outputs
outputs: ## print terraform outputs
	cd $(TF_DIR) && terraform output

.PHONY: ingest
ingest: ## invoke the lambda with default sizing (override STATIONS=, DAYS=)
	@FN=$$(cd $(TF_DIR) && terraform output -raw ingester_function_name) && \
	aws lambda invoke \
		--function-name $$FN \
		--cli-binary-format raw-in-base64-out \
		--payload '{"stations": $(STATIONS), "days": $(DAYS)}' \
		--cli-read-timeout 900 \
		/tmp/ingest-response.json && \
	cat /tmp/ingest-response.json | jq .

.PHONY: ingest-large
ingest-large: ## run the bigger benchmark workload (5000 stations x 365 days)
	$(MAKE) ingest STATIONS=5000 DAYS=365

.PHONY: query
query: duckdb/.attach.sql ## open duckdb attached to the s3 tables catalog
	@command -v duckdb >/dev/null 2>&1 || { \
	  echo "ERROR: duckdb CLI not found on PATH."; \
	  echo "Install it with one of:"; \
	  echo "  macOS:        brew install duckdb"; \
	  echo "  Linux/Win:    https://duckdb.org/docs/installation/"; \
	  echo "(The Python 'duckdb' package is a library, not a CLI.)"; \
	  exit 1; \
	}
	duckdb -init duckdb/01_setup.sql

duckdb/.attach.sql: $(wildcard $(TF_DIR)/terraform.tfstate*)
	@TB_ARN=$$(cd $(TF_DIR) && terraform output -raw table_bucket_arn 2>/dev/null) ; \
	if [ -z "$$TB_ARN" ]; then \
	  echo "ERROR: no terraform state - run 'make apply' first" >&2; exit 1; \
	fi ; \
	{ \
	  echo "-- Generated by 'make query'. Do not commit." ; \
	  echo "CREATE OR REPLACE SECRET aws_creds (" ; \
	  echo "    TYPE s3, PROVIDER credential_chain, PROFILE '$(AWS_PROFILE)'" ; \
	  echo ");" ; \
	  echo "ATTACH '$$TB_ARN' AS lake (TYPE iceberg, ENDPOINT_TYPE s3_tables);" ; \
	} > duckdb/.attach.sql ; \
	echo "wrote duckdb/.attach.sql"

.PHONY: seed-local
seed-local: ## build a local /tmp/openaq_local.duckdb for the migration demo
	uv run python scripts/seed_local.py

.PHONY: bench
bench: ## run the latency benchmark suite (writes results to docs/perf.md)
	uv run python scripts/bench.py

.PHONY: local-api
local-api: ## start the local duckdb API on localhost:8000 (used by the frontend)
	uv run python scripts/local_api.py

.PHONY: frontend
frontend: ## start the Vite dev server on localhost:5173
	cd frontend && npm install && npm run dev

.PHONY: frontend-build
frontend-build: ## build the frontend for production
	cd frontend && npm install && npm run build

.PHONY: logs
logs: ## tail ingester logs
	@FN=$$(cd $(TF_DIR) && terraform output -raw ingester_function_name) && \
	aws logs tail /aws/lambda/$$FN --follow --since 10m

.PHONY: empty-tables
empty-tables: ## drop all rows + snapshots so terraform destroy can succeed
	uv run python scripts/empty_tables.py

.PHONY: destroy
destroy: empty-tables ## tear down all infra
	cd $(TF_DIR) && terraform destroy

.PHONY: clean
clean: ## remove local build artifacts
	rm -rf ingester/dist ingester/layer/python
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .ruff_cache -exec rm -rf {} + 2>/dev/null || true
