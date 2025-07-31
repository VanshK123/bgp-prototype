# BGP Routing Algorithm Prototype Makefile
# Comprehensive build and deployment automation

.PHONY: help install deploy test clean cleanup logs monitor performance build-c

# Configuration
PROJECT_NAME := bgp-prototype
PYTHON := python3
PIP := pip3
TERRAFORM := terraform
AWS_CLI := aws

# Directories
SRC_DIR := src
TESTS_DIR := tests
AWS_DIR := aws
CONFIG_DIR := config
LOGS_DIR := logs
BUILD_DIR := build

# Files
CONFIG_FILE := $(CONFIG_DIR)/bgp_config.yaml
REQUIREMENTS_FILE := requirements.txt
DEPLOY_SCRIPT := $(SRC_DIR)/shell/deploy_bgp.sh
AUTOMATION_SCRIPT := $(SRC_DIR)/python/bgp_automation.py
TEST_FILE := $(TESTS_DIR)/test_bgp_performance.py

# Default target
help:
	@echo "BGP Routing Algorithm Prototype"
	@echo "================================"
	@echo ""
	@echo "Available targets:"
	@echo "  install     - Install Python dependencies"
	@echo "  deploy      - Deploy complete BGP topology"
	@echo "  test        - Run performance and integration tests"
	@echo "  clean       - Clean up AWS resources"
	@echo "  logs        - View deployment logs"
	@echo "  monitor     - Monitor BGP topology"
	@echo "  performance - Run performance benchmarks"
	@echo "  build-c     - Build C-based optimizations"
	@echo "  validate    - Validate configuration"
	@echo "  setup       - Initial project setup"
	@echo "  help        - Show this help message"

# Install dependencies
install:
	@echo "Installing Python dependencies..."
	$(PIP) install -r $(REQUIREMENTS_FILE)
	@echo "Installing development tools..."
	$(PIP) install black flake8 mypy isort
	@echo "Dependencies installed successfully"

# Validate configuration
validate:
	@echo "Validating configuration..."
	@if [ ! -f $(CONFIG_FILE) ]; then \
		echo "Error: Configuration file not found: $(CONFIG_FILE)"; \
		exit 1; \
	fi
	@$(PYTHON) -c "import yaml; yaml.safe_load(open('$(CONFIG_FILE)'))" || \
		(echo "Error: Invalid YAML syntax in $(CONFIG_FILE)" && exit 1)
	@echo "Configuration validation passed"

# Setup project
setup: install validate
	@echo "Setting up project directories..."
	@mkdir -p $(LOGS_DIR) $(BUILD_DIR)
	@chmod +x $(DEPLOY_SCRIPT)
	@echo "Project setup completed"

# Deploy BGP topology
deploy: validate
	@echo "Starting BGP topology deployment..."
	@$(DEPLOY_SCRIPT) deploy

# Run tests
test: validate
	@echo "Running BGP performance tests..."
	@$(PYTHON) -m pytest $(TEST_FILE) -v --tb=short
	@echo "Running automation tests..."
	@$(PYTHON) $(AUTOMATION_SCRIPT)

# Clean up AWS resources
clean:
	@echo "Cleaning up AWS resources..."
	@$(DEPLOY_SCRIPT) cleanup

# View logs
logs:
	@echo "Recent deployment logs:"
	@if [ -f $(LOGS_DIR)/deployment.log ]; then \
		tail -50 $(LOGS_DIR)/deployment.log; \
	else \
		echo "No deployment logs found"; \
	fi

# Monitor topology
monitor:
	@echo "Monitoring BGP topology..."
	@$(PYTHON) -c "
import boto3
import json
from datetime import datetime

ec2 = boto3.client('ec2')
instances = ec2.describe_instances(
    Filters=[{'Name': 'tag:Project', 'Values': ['bgp-prototype']}]
)

print('BGP Topology Status:')
print('====================')
for reservation in instances['Reservations']:
    for instance in reservation['Instances']:
        name = next((tag['Value'] for tag in instance['Tags'] if tag['Key'] == 'Name'), 'Unknown')
        state = instance['State']['Name']
        public_ip = instance.get('PublicIpAddress', 'N/A')
        print(f'{name}: {state} ({public_ip})')
"

# Run performance benchmarks
performance: validate
	@echo "Running performance benchmarks..."
	@$(PYTHON) -m pytest $(TEST_FILE) -m performance -v
	@echo "Performance benchmarks completed"

# Build C optimizations
build-c:
	@echo "Building C-based optimizations..."
	@mkdir -p $(BUILD_DIR)
	@gcc -O3 -Wall -Wextra -std=c99 \
		$(SRC_DIR)/c/route_lookup.c \
		-o $(BUILD_DIR)/route_lookup_test \
		-lm
	@echo "C optimizations built successfully"

# Run C performance test
test-c: build-c
	@echo "Testing C-based route lookup performance..."
	@$(BUILD_DIR)/route_lookup_test

# Format code
format:
	@echo "Formatting Python code..."
	@black $(SRC_DIR)/python/ $(TESTS_DIR)/
	@isort $(SRC_DIR)/python/ $(TESTS_DIR)/

# Lint code
lint:
	@echo "Linting Python code..."
	@flake8 $(SRC_DIR)/python/ $(TESTS_DIR)/
	@mypy $(SRC_DIR)/python/ $(TESTS_DIR)/

# Run full test suite
test-all: lint test performance test-c
	@echo "All tests completed"

# Deploy with performance testing
deploy-test: deploy test performance
	@echo "Deployment with testing completed"

# Nightly regression testing
nightly: validate
	@echo "Running nightly regression tests..."
	@$(PYTHON) -m pytest $(TEST_FILE) -v --tb=short
	@$(PYTHON) $(AUTOMATION_SCRIPT)
	@echo "Nightly regression tests completed"

# Generate performance report
report:
	@echo "Generating performance report..."
	@$(PYTHON) -c "
import json
import yaml
from datetime import datetime

# Load configuration
with open('$(CONFIG_FILE)', 'r') as f:
    config = yaml.safe_load(f)

# Generate report
report = {
    'project': 'BGP Routing Algorithm Prototype',
    'timestamp': datetime.now().isoformat(),
    'performance_targets': {
        'route_lookup_improvement': '25%',
        'cpu_utilization_improvement': '15%',
        'memory_efficiency_improvement': '20%',
        'test_coverage_improvement': '40%',
        'manual_testing_reduction': '50%'
    },
    'topology': {
        'router_count': config['aws']['router_count'],
        'instance_type': config['aws']['instance_type'],
        'availability_zones': len(config['aws']['availability_zones'])
    },
    'technologies': [
        'C (Performance optimizations)',
        'Python (Automation & testing)',
        'Shell (Deployment scripts)',
        'Linux (Operating system)',
        'FRR (BGP routing)',
        'Git (Version control)',
        'AWS EC2 (Cloud infrastructure)',
        'AWS S3 (Log storage)'
    ]
}

print(json.dumps(report, indent=2))
" > $(BUILD_DIR)/performance_report.json
	@echo "Performance report generated: $(BUILD_DIR)/performance_report.json"

# Show project status
status:
	@echo "BGP Project Status:"
	@echo "==================="
	@echo "Configuration: $(shell [ -f $(CONFIG_FILE) ] && echo "✓ Valid" || echo "✗ Missing")"
	@echo "Dependencies: $(shell $(PYTHON) -c "import boto3, paramiko, yaml" 2>/dev/null && echo "✓ Installed" || echo "✗ Missing")"
	@echo "AWS Credentials: $(shell $(AWS_CLI) sts get-caller-identity >/dev/null 2>&1 && echo "✓ Configured" || echo "✗ Not configured")"
	@echo "Terraform: $(shell command -v $(TERRAFORM) >/dev/null && echo "✓ Installed" || echo "✗ Missing")"
	@echo "Deployment Script: $(shell [ -x $(DEPLOY_SCRIPT) ] && echo "✓ Executable" || echo "✗ Not executable")"

# Quick deployment (minimal validation)
quick-deploy:
	@echo "Quick deployment (minimal validation)..."
	@$(DEPLOY_SCRIPT) deploy

# Development mode
dev: install format lint
	@echo "Development environment ready"

# Production deployment
prod: validate deploy test performance report
	@echo "Production deployment completed"

# Show help for specific target
help-%:
	@echo "Help for target '$*':"
	@echo "========================"
	@case '$*' in \
		deploy) echo "Deploys the complete BGP topology including AWS infrastructure, FRR configuration, and performance testing" ;; \
		test) echo "Runs comprehensive performance and integration tests" ;; \
		clean) echo "Removes all AWS resources created by the deployment" ;; \
		performance) echo "Runs performance benchmarks and generates metrics" ;; \
		build-c) echo "Compiles C-based route lookup optimizations" ;; \
		*) echo "No specific help available for '$*'" ;; \
	esac 