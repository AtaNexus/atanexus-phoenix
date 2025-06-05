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
BACKUP_BUCKET="${BACKUP_BUCKET:-${PROJECT_ID}-phoenix-backups}"

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

# Ensure backup bucket exists
ensure_backup_bucket() {
    if ! gsutil ls -b gs://"$BACKUP_BUCKET" &> /dev/null; then
        log_info "Creating backup bucket: gs://$BACKUP_BUCKET"
        gsutil mb gs://"$BACKUP_BUCKET"
        
        # Set lifecycle policy to delete backups older than 30 days
        cat > /tmp/lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 30}
      }
    ]
  }
}
EOF
        gsutil lifecycle set /tmp/lifecycle.json gs://"$BACKUP_BUCKET"
        rm /tmp/lifecycle.json
        log_info "Bucket created with 30-day retention policy"
    else
        log_info "Using existing backup bucket: gs://$BACKUP_BUCKET"
    fi
}

# Backup Phoenix data to GCS
backup() {
    log_info "Creating backup of Phoenix data..."
    check_instance
    
    # Ensure backup bucket exists
    ensure_backup_bucket
    
    BACKUP_NAME="phoenix-backup-$(date +%Y%m%d-%H%M%S)"
    BACKUP_PATH="/tmp/$BACKUP_NAME.tar.gz"
    GCS_PATH="gs://$BACKUP_BUCKET/$BACKUP_NAME.tar.gz"
    
    log_info "Creating backup archive on instance..."
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
        sudo tar -czf $BACKUP_PATH -C /opt/phoenix data/
        echo 'Backup created: $BACKUP_PATH'
        ls -lh $BACKUP_PATH
    "
    
    log_info "Uploading backup to GCS: $GCS_PATH"
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
        # Upload to GCS
        gsutil cp $BACKUP_PATH $GCS_PATH
        
        # Verify upload
        if gsutil ls $GCS_PATH &> /dev/null; then
            echo 'Backup successfully uploaded to GCS'
            # Clean up local file
            sudo rm $BACKUP_PATH
            echo 'Local backup file cleaned up'
        else
            echo 'ERROR: Failed to upload backup to GCS'
            exit 1
        fi
    "
    
    log_info "Backup completed successfully!"
    log_info "Backup location: $GCS_PATH"
    log_info "To download: gsutil cp $GCS_PATH ./"
    log_info "To list all backups: gsutil ls gs://$BACKUP_BUCKET/"
}

# List available backups
list_backups() {
    log_info "Listing available backups..."
    ensure_backup_bucket
    
    echo "Available backups in gs://$BACKUP_BUCKET:"
    gsutil ls -l gs://"$BACKUP_BUCKET"/phoenix-backup-*.tar.gz 2>/dev/null | sort -k2 -r || {
        log_warn "No backups found in gs://$BACKUP_BUCKET"
    }
}

# Restore Phoenix data from GCS backup
restore() {
    if [[ $# -eq 0 ]]; then
        log_error "Please specify a backup file to restore"
        echo "Usage: $0 restore <backup-filename>"
        echo ""
        echo "Available backups:"
        list_backups
        exit 1
    fi
    
    BACKUP_FILE="$1"
    GCS_PATH="gs://$BACKUP_BUCKET/$BACKUP_FILE"
    
    log_info "Restoring Phoenix data from: $GCS_PATH"
    check_instance
    
    # Verify backup exists
    if ! gsutil ls "$GCS_PATH" &> /dev/null; then
        log_error "Backup file not found: $GCS_PATH"
        echo ""
        echo "Available backups:"
        list_backups
        exit 1
    fi
    
    log_warn "This will replace all current Phoenix data!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restore cancelled"
        return
    fi
    
    log_info "Stopping Phoenix service..."
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="sudo systemctl stop phoenix"
    
    log_info "Downloading and restoring backup..."
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
        # Download backup
        gsutil cp $GCS_PATH /tmp/restore.tar.gz
        
        # Backup current data
        sudo mv /opt/phoenix/data /opt/phoenix/data.backup.\$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
        
        # Extract backup
        sudo mkdir -p /opt/phoenix
        sudo tar -xzf /tmp/restore.tar.gz -C /opt/phoenix/
        sudo chown -R phoenix:phoenix /opt/phoenix/data
        
        # Clean up
        rm /tmp/restore.tar.gz
        
        echo 'Restore completed successfully'
    "
    
    log_info "Starting Phoenix service..."
    gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="sudo systemctl start phoenix"
    
    log_info "Restore completed successfully!"
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
    echo "  status        Show instance and Phoenix service status"
    echo "  start         Start the instance"
    echo "  stop          Stop the instance"
    echo "  restart       Restart the instance"
    echo "  logs          Show Phoenix logs (follow mode)"
    echo "  ssh           SSH into the instance"
    echo "  update        Update Phoenix to the latest version"
    echo "  backup        Create and upload backup to GCS"
    echo "  list-backups  List available backups in GCS"
    echo "  restore       Restore from GCS backup (usage: restore <backup-filename>)"
    echo "  resources     Show resource usage"
    echo "  delete        Delete the instance (WARNING: destructive)"
    echo "  help          Show this help message"
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
        status|start|stop|restart|logs|ssh|update|backup|list-backups|restore|resources|delete|help)
            COMMAND="$1"
            shift
            # Handle restore command with argument
            if [[ "$COMMAND" == "restore" && $# -gt 0 ]]; then
                RESTORE_FILE="$1"
                shift
            fi
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
    list-backups)
        list_backups
        ;;
    restore)
        restore "$RESTORE_FILE"
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