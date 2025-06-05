#!/bin/bash

# Arize Phoenix GCP Compute Engine Deployment Script
# This script deploys Arize Phoenix to a GCP Compute Engine instance

set -euo pipefail

# Load configuration from phoenix-config.local.env if it exists
if [[ -f "phoenix-config.local.env" ]]; then
    echo "Loading configuration from phoenix-config.local.env..."
    source phoenix-config.local.env
elif [[ -f "phoenix-config.env" ]]; then
    echo "Loading configuration from phoenix-config.env..."
    source phoenix-config.env
fi

# Configuration - Update these variables as needed
PROJECT_ID="${PROJECT_ID:-your-gcp-project-id}"
INSTANCE_NAME="${INSTANCE_NAME:-phoenix-server}"
ZONE="${ZONE:-us-central1-a}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-2}"
DISK_SIZE="${DISK_SIZE:-20GB}"
PHOENIX_PORT="${PHOENIX_PORT:-6006}"
PHOENIX_VERSION="${PHOENIX_VERSION:-latest}"

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

# Check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_info "Prerequisites check passed!"
}

# Set the active project
set_project() {
    log_info "Setting GCP project to: $PROJECT_ID"
    gcloud config set project "$PROJECT_ID"
}

# Create firewall rule for Phoenix
create_firewall_rule() {
    log_info "Creating firewall rule for Phoenix port $PHOENIX_PORT..."
    
    if gcloud compute firewall-rules describe phoenix-allow-$PHOENIX_PORT &> /dev/null; then
        log_warn "Firewall rule phoenix-allow-$PHOENIX_PORT already exists"
    else
        gcloud compute firewall-rules create phoenix-allow-$PHOENIX_PORT \
            --allow tcp:$PHOENIX_PORT \
            --source-ranges 0.0.0.0/0 \
            --description "Allow Phoenix web interface" \
            --target-tags phoenix-server
        log_info "Firewall rule created successfully"
    fi
}

# Create the startup script
create_startup_script() {
    log_info "Creating startup script..."
    
    cat > startup-script.sh << 'EOF'
#!/bin/bash

# Update system
apt-get update
apt-get install -y python3 python3-pip python3-venv docker.io

# Start Docker service
systemctl start docker
systemctl enable docker

# Create phoenix user
useradd -m -s /bin/bash phoenix || true
usermod -aG docker phoenix

# Create directory for Phoenix
mkdir -p /opt/phoenix
chown phoenix:phoenix /opt/phoenix

# Create systemd service for Phoenix
cat > /etc/systemd/system/phoenix.service << 'PHOENIX_SERVICE'
[Unit]
Description=Arize Phoenix Server
After=docker.service
Requires=docker.service

[Service]
Type=exec
User=phoenix
Group=phoenix
WorkingDirectory=/opt/phoenix
ExecStartPre=/usr/bin/docker pull arizephoenix/phoenix:PHOENIX_VERSION_PLACEHOLDER
ExecStart=/usr/bin/docker run --rm --name phoenix \
    -p PHOENIX_PORT_PLACEHOLDER:6006 \
    -v /opt/phoenix/data:/phoenix/data \
    -e PHOENIX_SQL_DATABASE_URL=sqlite:////phoenix/data/phoenix.db \
    arizephoenix/phoenix:PHOENIX_VERSION_PLACEHOLDER
ExecStop=/usr/bin/docker stop phoenix
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
PHOENIX_SERVICE

# Replace placeholders in service file
sed -i "s/PHOENIX_VERSION_PLACEHOLDER/PHOENIX_VERSION_VALUE/g" /etc/systemd/system/phoenix.service
sed -i "s/PHOENIX_PORT_PLACEHOLDER/PHOENIX_PORT_VALUE/g" /etc/systemd/system/phoenix.service

# Create data directory
mkdir -p /opt/phoenix/data
chown -R phoenix:phoenix /opt/phoenix

# Enable and start Phoenix service
systemctl daemon-reload
systemctl enable phoenix
systemctl start phoenix

# Log the startup completion
echo "Phoenix deployment completed at $(date)" >> /opt/phoenix/deployment.log
EOF

    # Replace placeholders in startup script
    sed -i "s/PHOENIX_VERSION_VALUE/$PHOENIX_VERSION/g" startup-script.sh
    sed -i "s/PHOENIX_PORT_VALUE/$PHOENIX_PORT/g" startup-script.sh
    
    log_info "Startup script created"
}

# Create the VM instance
create_instance() {
    log_info "Creating GCP Compute Engine instance: $INSTANCE_NAME"
    
    if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &> /dev/null; then
        log_warn "Instance $INSTANCE_NAME already exists in zone $ZONE"
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing instance..."
            gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet
        else
            log_info "Skipping instance creation"
            return
        fi
    fi
    
    gcloud compute instances create "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --network-tier=PREMIUM \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --service-account="$PROJECT_ID@appspot.gserviceaccount.com" \
        --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
        --tags=phoenix-server \
        --create-disk=auto-delete=yes,boot=yes,device-name="$INSTANCE_NAME",image=projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts,mode=rw,size="$DISK_SIZE",type=projects/"$PROJECT_ID"/zones/"$ZONE"/diskTypes/pd-standard \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=app=phoenix,environment=production \
        --reservation-affinity=any \
        --metadata-from-file startup-script=startup-script.sh
    
    log_info "Instance created successfully!"
}

# Get instance information
get_instance_info() {
    log_info "Getting instance information..."
    
    EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    INTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --format='get(networkInterfaces[0].networkIP)')
    
    echo ""
    log_info "Deployment completed successfully!"
    echo "==========================================="
    echo "Instance Name: $INSTANCE_NAME"
    echo "Zone: $ZONE"
    echo "External IP: $EXTERNAL_IP"
    echo "Internal IP: $INTERNAL_IP"
    echo "Phoenix URL: http://$EXTERNAL_IP:$PHOENIX_PORT"
    echo "==========================================="
    echo ""
    log_info "Phoenix is starting up. It may take a few minutes to be accessible."
    log_info "You can check the startup progress with:"
    echo "  gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='sudo journalctl -u phoenix -f'"
}

# Main deployment function
deploy() {
    log_info "Starting Arize Phoenix deployment to GCP Compute Engine"
    log_info "Project: $PROJECT_ID"
    log_info "Instance: $INSTANCE_NAME"
    log_info "Zone: $ZONE"
    log_info "Machine Type: $MACHINE_TYPE"
    echo ""
    
    check_prerequisites
    set_project
    create_firewall_rule
    create_startup_script
    create_instance
    get_instance_info
}

# Parse command line arguments
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
        -m|--machine-type)
            MACHINE_TYPE="$2"
            shift 2
            ;;
        --port)
            PHOENIX_PORT="$2"
            shift 2
            ;;
        --version)
            PHOENIX_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --project PROJECT_ID     GCP Project ID"
            echo "  -n, --name INSTANCE_NAME     Instance name (default: phoenix-server)"
            echo "  -z, --zone ZONE              GCP Zone (default: us-central1-a)"
            echo "  -m, --machine-type TYPE      Machine type (default: e2-standard-2)"
            echo "  --port PORT                  Phoenix port (default: 6006)"
            echo "  --version VERSION            Phoenix version (default: latest)"
            echo "  -h, --help                   Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  PROJECT_ID, INSTANCE_NAME, ZONE, MACHINE_TYPE, PHOENIX_PORT, PHOENIX_VERSION"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ "$PROJECT_ID" == "your-gcp-project-id" ]]; then
    log_error "Please set PROJECT_ID either via environment variable or --project flag"
    exit 1
fi

# Run deployment
deploy 