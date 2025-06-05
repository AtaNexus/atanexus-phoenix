#!/bin/bash

# Arize Phoenix GCP Management Script
# This script helps manage the deployed Phoenix instance

set -euo pipefail

# Load configuration from phoenix-config.local.env if it exists
if [[ -f "phoenix-config.local.env" ]]; then
    echo "Loading configuration from phoenix-config.local.env..."
    source phoenix-config.local.env
elif [[ -f "phoenix-config.env" ]]; then
    echo "Loading configuration from phoenix-config.env..."
    source phoenix-config.env
fi

# Default configuration
PROJECT_ID="${PROJECT_ID:-your-gcp-project-id}"
INSTANCE_NAME="${INSTANCE_NAME:-phoenix-server}"
ZONE="${ZONE:-us-central1-a}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if instance exists
check_instance() {
    if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &> /dev/null; then
        log_error "Instance $INSTANCE_NAME not found in zone $ZONE"
        exit 1
    fi
}

# Get instance status
status() {
    log_info "Getting Phoenix instance status..."
    check_instance
    
    STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format='get(status)')
    EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    echo "Instance Status: $STATUS"
    echo "External IP: $EXTERNAL_IP"
    
    if [[ "$STATUS" == "RUNNING" ]]; then
        log_info "Checking Phoenix service status..."
        gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command='sudo systemctl is-active phoenix' || true
        echo "Phoenix URL: http://$EXTERNAL_IP:6006"
    fi
}

# Start the instance
start() {
    log_info "Starting Phoenix instance..."
    check_instance
    gcloud compute instances start "$INSTANCE_NAME" --zone="$ZONE"
    log_info "Instance started successfully!"
}

# Stop the instance
stop() {
    log_info "Stopping Phoenix instance..."
    check_instance
    gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE"
    log_info "Instance stopped successfully!"
}

# Restart the instance
restart() {
    log_info "Restarting Phoenix instance..."
    check_instance
    gcloud compute instances reset "$INSTANCE_NAME" --zone="$ZONE"
    log_info "Instance restarted successfully!"
}

# Show logs
logs() {
    log_info "Showing Phoenix logs..."
    check_instance
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command='sudo journalctl -u phoenix -f'
}

# SSH into the instance
ssh() {
    log_info "Connecting to Phoenix instance..."
    check_instance
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE"
}

# Update Phoenix
update() {
    log_info "Updating Phoenix..."
    check_instance
    
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command='
        sudo systemctl stop phoenix
        sudo docker pull arizephoenix/phoenix:latest
        sudo systemctl start phoenix
        echo "Phoenix updated successfully!"
    '
}

# Backup Phoenix data
backup() {
    log_info "Creating backup of Phoenix data..."
    check_instance
    
    BACKUP_NAME="phoenix-backup-$(date +%Y%m%d-%H%M%S)"
    
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
        sudo tar -czf /tmp/$BACKUP_NAME.tar.gz -C /opt/phoenix data/
        echo 'Backup created: /tmp/$BACKUP_NAME.tar.gz'
    "
    
    # Download backup
    gcloud compute scp "$INSTANCE_NAME:/tmp/$BACKUP_NAME.tar.gz" ./ --zone="$ZONE"
    log_info "Backup downloaded to: $BACKUP_NAME.tar.gz"
}

# Show resource usage
resources() {
    log_info "Showing resource usage..."
    check_instance
    
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command='
        echo "=== CPU and Memory Usage ==="
        free -h
        echo ""
        echo "=== Disk Usage ==="
        df -h
        echo ""
        echo "=== Phoenix Container Stats ==="
        sudo docker stats phoenix --no-stream 2>/dev/null || echo "Phoenix container not running"
    '
}

# Delete the instance
delete() {
    log_warn "This will permanently delete the Phoenix instance and all data!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deleting Phoenix instance..."
        gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet
        log_info "Instance deleted successfully!"
    else
        log_info "Operation cancelled"
    fi
}

# Show help
help() {
    echo "Phoenix GCP Management Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  status      Show instance and Phoenix service status"
    echo "  start       Start the instance"
    echo "  stop        Stop the instance"
    echo "  restart     Restart the instance"
    echo "  logs        Show Phoenix logs (follow mode)"
    echo "  ssh         SSH into the instance"
    echo "  update      Update Phoenix to the latest version"
    echo "  backup      Create and download a backup of Phoenix data"
    echo "  resources   Show resource usage"
    echo "  delete      Delete the instance (WARNING: destructive)"
    echo "  help        Show this help message"
    echo ""
    echo "Options:"
    echo "  -p, --project PROJECT_ID     GCP Project ID"
    echo "  -n, --name INSTANCE_NAME     Instance name (default: phoenix-server)"
    echo "  -z, --zone ZONE              GCP Zone (default: us-central1-a)"
    echo ""
    echo "Environment variables:"
    echo "  PROJECT_ID, INSTANCE_NAME, ZONE"
}

# Parse command line arguments
COMMAND=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        -n|--name)
            INSTANCE_NAME="$2"
            shift 2
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        status|start|stop|restart|logs|ssh|update|backup|resources|delete|help)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ "$PROJECT_ID" == "your-gcp-project-id" ]]; then
    log_error "Please set PROJECT_ID either via environment variable or --project flag"
    exit 1
fi

if [[ -z "$COMMAND" ]]; then
    log_error "Please specify a command"
    help
    exit 1
fi

# Set GCP project
gcloud config set project "$PROJECT_ID" 2>/dev/null

# Execute command
case $COMMAND in
    status)
        status
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    logs)
        logs
        ;;
    ssh)
        ssh
        ;;
    update)
        update
        ;;
    backup)
        backup
        ;;
    resources)
        resources
        ;;
    delete)
        delete
        ;;
    help)
        help
        ;;
esac 