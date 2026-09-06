# ==============================================================================
# Serverless DevSecOps & FinOps Pipeline Developer CLI
# ==============================================================================

.PHONY: help install test test-unit test-chaos audit verify-cosign bench status optimize dashboard clean

SHELL := /bin/bash
PYTHON ?= python3

# Colors for terminal styling
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BOLD := \033[1m
NC := \033[0m

help: ## Show this help message and exit
	@echo -e "${CYAN}${BOLD}"
	@echo "=============================================================="
	@echo " Serverless DevSecOps & FinOps Pipeline CLI"
	@echo "=============================================================="
	@echo -e "${NC}"
	@echo -e "${YELLOW}Usage:${NC} make [target]"
	@echo ""
	@echo -e "${BOLD}Verification & Quality Targets:${NC}"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${GREEN}%-18s${NC} %s\n", $$1, $$2}'
	@echo ""

install: ## Install development & testing dependencies
	@echo -e "${CYAN}[*] Installing development dependencies...${NC}"
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install -r requirements-dev.txt

test: test-unit test-chaos ## Run complete unit and resilience test suites

test-unit: ## Run the 10/10 automated DevSecOps unit test suite
	@echo -e "${CYAN}[*] Running 10/10 Automated DevSecOps Unit Tests...${NC}"
	$(PYTHON) -m unittest discover -s function/image-processor-app -p "*_test.py"

test-chaos: ## Run the 5/5 Chaos Engineering & OpenTelemetry tracing tests
	@echo -e "${CYAN}[*] Running 5/5 Chaos Fault Injection & Distributed Tracing Suite...${NC}"
	$(PYTHON) testing_suite/5_chaos_and_tracing_test.py

audit: ## Execute live 10/10 Enterprise DevSecOps compliance audit
	@echo -e "${CYAN}[*] Executing Live 10/10 Enterprise DevSecOps Audit...${NC}"
	$(PYTHON) security_suite/1_run_security_audit.py

verify-cosign: ## Verify Cosign NIST P-256 ECDSA container cryptographic signature
	@echo -e "${CYAN}[*] Verifying Cosign Supply-Chain Cryptographic Container Signature...${NC}"
	$(PYTHON) security_suite/2_verify_cosign_signature.py

bench: ## Execute multi-tier FinOps cloud cost & latency benchmark
	@echo -e "${CYAN}[*] Executing FinOps Latency Percentile & Cost Reduction Benchmark...${NC}"
	$(PYTHON) testing_suite/3_finops_cost_benchmark.py

status: ## Inspect live Kubernetes cluster status and pod fleet
	@./cluster_manage.sh status

optimize: ## Reconcile Zero-Trust policies, 32MB RAM disk, and rolling restart
	@./cluster_manage.sh optimize

dashboard: ## Launch the real-time observability control plane on port 8888
	@echo -e "${GREEN}[✓] Starting Dashboard on http://localhost:8888 ...${NC}"
	$(PYTHON) dashboard/server.py

clean: ## Clean up build artifacts, cache files, and bytecode
	@echo -e "${CYAN}[*] Cleaning temporary files and pycache...${NC}"
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.py[cod]" -delete
	rm -rf .pytest_cache .coverage htmlcov .tox
	@echo -e "${GREEN}[✓] Cleanup complete!${NC}"
