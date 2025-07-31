#!/bin/bash
# BGP Topology Deployment Script
# Deploys 10-node BGP topology on AWS with FRR integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PROJECT_ROOT/config/bgp_config.yaml"
LOG_FILE="$PROJECT_ROOT/logs/deployment.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO"' ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("terraform" "aws" "python3" "pip3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check Python dependencies
    if ! python3 -c "import boto3, paramiko, yaml" &> /dev/null; then
        log_warning "Some Python dependencies missing, installing..."
        pip3 install -r "$PROJECT_ROOT/requirements.txt"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate configuration
validate_config() {
    log_info "Validating configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Validate YAML syntax
    if ! python3 -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))" &> /dev/null; then
        log_error "Invalid YAML syntax in configuration file"
        exit 1
    fi
    
    log_success "Configuration validation completed"
}

# Function to deploy AWS infrastructure
deploy_aws_infrastructure() {
    log_info "Deploying AWS infrastructure..."
    
    cd "$PROJECT_ROOT/aws/terraform"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    # Apply deployment
    log_info "Applying Terraform deployment..."
    terraform apply tfplan
    
    # Get outputs
    log_info "Getting deployment outputs..."
    ROUTER_PUBLIC_IPS=$(terraform output -raw router_public_ips)
    ROUTER_PRIVATE_IPS=$(terraform output -raw router_private_ips)
    S3_BUCKET=$(terraform output -raw s3_bucket_name)
    
    log_success "AWS infrastructure deployment completed"
}

# Function to wait for routers to be ready
wait_for_routers() {
    log_info "Waiting for routers to be ready..."
    
    local timeout=600  # 10 minutes
    local start_time=$(date +%s)
    local ready_count=0
    local total_routers=10
    
    while [[ $ready_count -lt $total_routers ]]; do
        ready_count=0
        
        for ip in $ROUTER_PUBLIC_IPS; do
            if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i ~/.ssh/bgp-key.pem ubuntu@"$ip" "echo 'SSH connection successful'" &> /dev/null; then
                ((ready_count++))
            fi
        done
        
        if [[ $(($(date +%s) - start_time)) -gt $timeout ]]; then
            log_error "Timeout waiting for routers to be ready"
            exit 1
        fi
        
        log_info "Routers ready: $ready_count/$total_routers"
        sleep 30
    done
    
    log_success "All routers are ready"
}

# Function to configure BGP sessions
configure_bgp_sessions() {
    log_info "Configuring BGP sessions..."
    
    local router_ips=($ROUTER_PUBLIC_IPS)
    local private_ips=($ROUTER_PRIVATE_IPS)
    
    for i in "${!router_ips[@]}"; do
        local router_id=$((i + 1))
        local public_ip="${router_ips[$i]}"
        local private_ip="${private_ips[$i]}"
        local asn=$((65000 + router_id))
        
        log_info "Configuring router $router_id (ASN: $asn)"
        
        # Generate BGP configuration
        local bgp_config=$(generate_bgp_config "$router_id" "$private_ip" "$asn" "$ROUTER_PRIVATE_IPS")
        
        # Upload and apply configuration
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/bgp-key.pem ubuntu@"$public_ip" "sudo tee /etc/frr/frr.conf > /dev/null" <<< "$bgp_config"
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/bgp-key.pem ubuntu@"$public_ip" "sudo systemctl restart frr"
        
        log_success "Router $router_id configured"
    done
    
    log_success "BGP sessions configuration completed"
}

# Function to generate BGP configuration
generate_bgp_config() {
    local router_id=$1
    local private_ip=$2
    local asn=$3
    local all_private_ips=$4
    
    local config="!
! FRR configuration for router $router_id
!
hostname bgp-router-$router_id
password zebra
enable password zebra
!
log file /var/log/frr/frr.log
!
router bgp $asn
 bgp router-id $private_ip
 network 10.0.$router_id.0/24
"
    
    # Add neighbors
    local ips=($all_private_ips)
    for i in "${!ips[@]}"; do
        local neighbor_id=$((i + 1))
        local neighbor_ip="${ips[$i]}"
        local neighbor_asn=$((65000 + neighbor_id))
        
        if [[ $neighbor_id -ne $router_id ]]; then
            config+=" neighbor $neighbor_ip remote-as $neighbor_asn"$'\n'
        fi
    done
    
    config+="!
line vty
!
"
    
    echo "$config"
}

# Function to inject test routes
inject_test_routes() {
    log_info "Injecting test routes..."
    
    local route_count=10000
    local router_ips=($ROUTER_PUBLIC_IPS)
    
    for i in "${!router_ips[@]}"; do
        local router_id=$((i + 1))
        local public_ip="${router_ips[$i]}"
        
        log_info "Injecting routes into router $router_id"
        
        # Create route injection script
        local injection_script=$(create_route_injection_script "$route_count")
        
        # Upload and execute script
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/bgp-key.pem ubuntu@"$public_ip" "cat > /tmp/inject_routes.py" <<< "$injection_script"
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/bgp-key.pem ubuntu@"$public_ip" "python3 /tmp/inject_routes.py"
        
        log_success "Routes injected into router $router_id"
    done
    
    log_success "Test route injection completed"
}

# Function to create route injection script
create_route_injection_script() {
    local route_count=$1
    
    cat << 'EOF'
#!/usr/bin/env python3
import subprocess
import time

def inject_routes():
    for i in range(10000):
        prefix = f"192.168.{i // 256}.{i % 256}"
        cmd = f'vtysh -c "configure terminal" -c "router bgp 65001" -c "network {prefix}/24"'
        subprocess.run(cmd, shell=True)
        
        if i % 1000 == 0:
            print(f"Injected {i} routes")
            time.sleep(0.1)

if __name__ == "__main__":
    inject_routes()
EOF
}

# Function to run performance tests
run_performance_tests() {
    log_info "Running performance tests..."
    
    cd "$PROJECT_ROOT"
    
    # Run Python performance tests
    python3 -m pytest tests/test_bgp_performance.py -v --tb=short
    
    log_success "Performance tests completed"
}

# Function to upload logs to S3
upload_logs_to_s3() {
    log_info "Uploading logs to S3..."
    
    local log_files=("$LOG_FILE" "$PROJECT_ROOT/logs/bgp-automation.log")
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            aws s3 cp "$log_file" "s3://$S3_BUCKET/logs/deployment/$TIMESTAMP/"
        fi
    done
    
    log_success "Logs uploaded to S3"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "========================================"
    echo "Project: BGP Routing Algorithm Prototype"
    echo "Deployment Time: $(date)"
    echo "Router Count: 10"
    echo "AWS Region: us-east-1"
    echo "S3 Bucket: $S3_BUCKET"
    echo "Public IPs: $ROUTER_PUBLIC_IPS"
    echo "Private IPs: $ROUTER_PRIVATE_IPS"
    echo "========================================"
}

# Function to cleanup on failure
cleanup_on_failure() {
    log_error "Deployment failed, starting cleanup..."
    
    cd "$PROJECT_ROOT/aws/terraform"
    terraform destroy -auto-approve
    
    log_warning "Cleanup completed"
}

# Main deployment function
main() {
    log_info "Starting BGP topology deployment"
    
    # Create logs directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate configuration
    validate_config
    
    # Deploy AWS infrastructure
    deploy_aws_infrastructure
    
    # Wait for routers
    wait_for_routers
    
    # Configure BGP sessions
    configure_bgp_sessions
    
    # Inject test routes
    inject_test_routes
    
    # Run performance tests
    run_performance_tests
    
    # Upload logs
    upload_logs_to_s3
    
    # Display summary
    display_summary
    
    log_success "BGP topology deployment completed successfully"
}

# Handle command line arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "cleanup")
        log_info "Starting cleanup..."
        cd "$PROJECT_ROOT/aws/terraform"
        terraform destroy -auto-approve
        log_success "Cleanup completed"
        ;;
    "test")
        log_info "Running tests only..."
        run_performance_tests
        ;;
    *)
        echo "Usage: $0 [deploy|cleanup|test]"
        exit 1
        ;;
esac 