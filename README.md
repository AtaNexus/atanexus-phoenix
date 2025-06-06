# Arize Phoenix GCP Deployment

This repository contains scripts to deploy and manage [Arize Phoenix](https://github.com/Arize-ai/phoenix) on Google Cloud Platform (GCP) Compute Engine.

## Prerequisites

Before using these scripts, ensure you have:

1. **Google Cloud SDK (gcloud)** installed and configured
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Authenticate with GCP
   gcloud auth login
   gcloud auth application-default login
   ```

2. **GCP Project** with the following APIs enabled:
   - Compute Engine API
   - Cloud Resource Manager API
   
   Enable them with:
   ```bash
   gcloud services enable compute.googleapis.com
   gcloud services enable cloudresourcemanager.googleapis.com
   ```

3. **Required IAM permissions** for your account:
   - Compute Instance Admin
   - Security Admin (for firewall rules)
   - Service Account User

## Quick Start

### 1. Configure Your Deployment

Copy the configuration template and customize it:

```bash
cp phoenix-config.env phoenix-config.local.env
```

Edit `phoenix-config.local.env` with your GCP project details:

```bash
PROJECT_ID=your-actual-gcp-project-id
INSTANCE_NAME=phoenix-server
ZONE=us-central1-a
MACHINE_TYPE=e2-standard-2
PHOENIX_PORT=6006
```

### 2. Deploy Phoenix

Make the deployment script executable and run it:

```bash
chmod +x deploy-phoenix-gcp.sh
./deploy-phoenix-gcp.sh
```

Note: The script automatically loads `phoenix-config.local.env` if it exists, so you don't need to source it manually.

Or specify configuration via command line:

```bash
./deploy-phoenix-gcp.sh --project your-project-id --name my-phoenix --zone us-west1-a
```

### 3. Access Phoenix

After deployment, the script will output the Phoenix URL:

```
Phoenix URL: http://YOUR-EXTERNAL-IP:6006
```

## Management

Use the management script to control your Phoenix instance:

```bash
chmod +x manage-phoenix.sh
```

Note: The management script also automatically loads your configuration file.

### Available Commands

```bash
# Check status
./manage-phoenix.sh status

# Start/stop/restart instance
./manage-phoenix.sh start
./manage-phoenix.sh stop
./manage-phoenix.sh restart

# View logs
./manage-phoenix.sh logs

# SSH into instance
./manage-phoenix.sh ssh

# Update Phoenix to latest version
./manage-phoenix.sh update

# Create backup (uploads to GCS)
./manage-phoenix.sh backup

# List available backups
./manage-phoenix.sh list-backups

# Restore from backup
./manage-phoenix.sh restore phoenix-backup-20231205-143022.tar.gz

# View resource usage
./manage-phoenix.sh resources

# Delete instance (WARNING: destructive)
./manage-phoenix.sh delete
```

## Configuration Options

### Deployment Script Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --project` | GCP Project ID | Required |
| `-n, --name` | Instance name | `phoenix-server` |
| `-z, --zone` | GCP Zone | `us-central1-a` |
| `-m, --machine-type` | Machine type | `e2-standard-2` |
| `--port` | Phoenix port | `6006` |
| `--version` | Phoenix version | `latest` |

### Environment Variables

You can also configure the deployment using environment variables:

```bash
export PROJECT_ID=your-project-id
export INSTANCE_NAME=my-phoenix
export ZONE=us-west1-a
export MACHINE_TYPE=e2-standard-4
export PHOENIX_PORT=6006
export PHOENIX_VERSION=latest
```

## Machine Type Recommendations

| Use Case | Machine Type | vCPUs | Memory | Cost/Month* |
|----------|--------------|-------|--------|-------------|
| Development | `e2-micro` | 2 | 1 GB | ~$6 |
| Small Production | `e2-standard-2` | 2 | 8 GB | ~$50 |
| Medium Production | `e2-standard-4` | 4 | 16 GB | ~$100 |
| Large Production | `e2-standard-8` | 8 | 32 GB | ~$200 |

*Approximate costs for us-central1 region

## Data Persistence

Phoenix data is stored in `/opt/phoenix/data/` on the instance and persists across:
- Container restarts
- Phoenix updates
- Instance reboots

**Important**: Data will be lost if you delete the instance. Use the backup feature regularly:

```bash
./manage-phoenix.sh backup
```

## Backup and Restore

Phoenix backups are automatically stored in Google Cloud Storage with the following features:

- **Automatic bucket creation** with 30-day retention policy
- **Compressed archives** for efficient storage
- **Timestamped backups** for easy identification
- **Easy restore** from any backup

### Backup Commands

```bash
# Create a backup
./manage-phoenix.sh backup

# List all available backups
./manage-phoenix.sh list-backups

# Restore from a specific backup
./manage-phoenix.sh restore phoenix-backup-20231205-143022.tar.gz
```

### Configuration

You can customize the backup bucket in your `phoenix-config.local.env`:

```bash
BACKUP_BUCKET=my-custom-backup-bucket
```

## Security Considerations

### Network Security
- The deployment creates a firewall rule allowing access to Phoenix port from any IP (`0.0.0.0/0`)
- For production, consider restricting access to specific IP ranges
- The instance has a public IP by default

### Recommended Security Improvements

1. **Restrict firewall access**:
   ```bash
   gcloud compute firewall-rules update phoenix-allow-6006 \
     --source-ranges="YOUR-OFFICE-IP/32,YOUR-VPN-IP/32"
   ```

2. **Use internal load balancer** for production deployments

3. **Enable OS Login** for better SSH key management:
   ```bash
   gcloud compute instances add-metadata phoenix-server \
     --metadata enable-oslogin=TRUE --zone=us-central1-a
   ```

## Troubleshooting

### Common Issues

1. **Phoenix not accessible after deployment**
   - Wait 2-3 minutes for the startup script to complete
   - Check the startup logs:
     ```bash
     ./manage-phoenix.sh ssh
     sudo journalctl -u phoenix -f
     ```

2. **Permission denied errors**
   - Ensure your account has the required IAM permissions
   - Verify you're authenticated: `gcloud auth list`

3. **Instance creation fails**
   - Check if you have sufficient quota in the selected zone
   - Try a different zone: `--zone us-west1-a`

4. **Port 6006 not accessible**
   - Verify firewall rule exists:
     ```bash
     gcloud compute firewall-rules describe phoenix-allow-6006
     ```

### Getting Help

1. **View deployment logs**:
   ```bash
   ./manage-phoenix.sh logs
   ```

2. **Check instance status**:
   ```bash
   ./manage-phoenix.sh status
   ```

3. **SSH into instance for debugging**:
   ```bash
   ./manage-phoenix.sh ssh
   ```

## Custom Domain Setup

### Binding Phoenix to https://phoenix.atanexus.com

To bind your Phoenix instance to a custom domain like `https://phoenix.atanexus.com`, follow these steps:

#### 1. DNS Configuration

First, you need to point your domain to your GCP instance's external IP:

```bash
# Get your instance's external IP
EXTERNAL_IP=$(gcloud compute instances describe ${INSTANCE_NAME:-atanexus-phoenix-server} \
  --zone=${ZONE:-us-central1-a} \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "Your instance external IP: $EXTERNAL_IP"
```

Then create an A record in your DNS provider (e.g., Cloudflare, Route 53, etc.):
- **Type**: A
- **Name**: phoenix.atanexus.com
- **Value**: `$EXTERNAL_IP` (the IP from above)
- **TTL**: 300 (or your preference)

#### 2. Install and Configure Nginx with SSL

SSH into your instance and set up a reverse proxy with SSL:

```bash
# SSH into your Phoenix instance
./manage-phoenix.sh ssh

# Install Nginx and Certbot
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

# Create Nginx configuration for Phoenix
sudo tee /etc/nginx/sites-available/phoenix.atanexus.com << 'EOF'
server {
    listen 80;
    server_name phoenix.atanexus.com;
    
    # Redirect all HTTP traffic to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name phoenix.atanexus.com;
    
    # SSL configuration (will be managed by Certbot)
    
    # Proxy configuration for Phoenix
    location / {
        proxy_pass http://localhost:6006;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support (if Phoenix uses WebSockets)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Increase timeout for long-running requests
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
}
EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/phoenix.atanexus.com /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
sudo nginx -t

# Start and enable Nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

#### 3. Obtain SSL Certificate

Once DNS propagation is complete (usually 5-15 minutes), obtain an SSL certificate:

```bash
# Still in the SSH session on your instance
sudo certbot --nginx -d phoenix.atanexus.com

# Follow the prompts:
# - Enter your email address
# - Agree to terms of service
# - Choose whether to share email with EFF
# - Select option 2 to redirect HTTP to HTTPS (recommended)
```

#### 4. Update Firewall Rules

Allow HTTPS traffic and optionally restrict HTTP/Phoenix port access:

```bash
# Exit SSH session first
exit

# Allow HTTPS traffic
gcloud compute firewall-rules create allow-https \
  --allow tcp:443 \
  --source-ranges 0.0.0.0/0 \
  --description "Allow HTTPS traffic"

# Allow HTTP traffic (for Certbot renewal)
gcloud compute firewall-rules create allow-http \
  --allow tcp:80 \
  --source-ranges 0.0.0.0/0 \
  --description "Allow HTTP traffic for SSL renewal"

# Optional: Restrict direct access to Phoenix port to localhost only
gcloud compute firewall-rules update phoenix-allow-6006 \
  --source-ranges 127.0.0.1/32 \
  --description "Restrict Phoenix port to localhost (behind Nginx proxy)"
```

#### 5. Auto-renewal Setup

Certbot automatically sets up a cron job for certificate renewal, but verify it:

```bash
# SSH back into the instance
./manage-phoenix.sh ssh

# Test auto-renewal
sudo certbot renew --dry-run

# Check cron job exists
sudo crontab -l
```

#### 6. Verification

After DNS propagation (5-30 minutes), verify your setup:

1. **Check DNS resolution**:
   ```bash
   nslookup phoenix.atanexus.com
   # Should return your instance IP
   ```

2. **Test HTTPS access**:
   ```bash
   curl -I https://phoenix.atanexus.com
   # Should return 200 OK
   ```

3. **Verify redirect**:
   ```bash
   curl -I http://phoenix.atanexus.com
   # Should return 301 redirect to HTTPS
   ```

#### 7. Update Your Configuration (Optional)

Update your local configuration to reflect the custom domain:

```bash
# Add to your phoenix-config.local.env
echo "PHOENIX_DOMAIN=phoenix.atanexus.com" >> phoenix-config.local.env
echo "PHOENIX_URL=https://phoenix.atanexus.com" >> phoenix-config.local.env
```

### Maintenance

#### SSL Certificate Renewal
Certbot auto-renews certificates, but you can manually renew:

```bash
./manage-phoenix.sh ssh
sudo certbot renew
sudo systemctl reload nginx
```

#### Nginx Configuration Updates
If you need to update Nginx configuration:

```bash
./manage-phoenix.sh ssh
sudo nano /etc/nginx/sites-available/phoenix.atanexus.com
sudo nginx -t
sudo systemctl reload nginx
```

#### Troubleshooting Domain Issues

1. **DNS not resolving**: Wait for propagation (up to 48 hours)
2. **SSL certificate issues**: Check Certbot logs: `sudo journalctl -u certbot`
3. **502 Bad Gateway**: Ensure Phoenix is running: `sudo systemctl status phoenix`
4. **Connection refused**: Check firewall rules and Nginx status

## Advanced Configuration

### Custom Docker Image

To use a custom Phoenix image:

```bash
# Edit the startup script before deployment
sed -i 's|arizephoenix/phoenix:latest|your-custom-image:tag|g' startup-script.sh
```

### Environment Variables

Add custom environment variables to Phoenix:

```bash
# Edit /etc/systemd/system/phoenix.service on the instance
ExecStart=/usr/bin/docker run --rm --name phoenix \
    -p 6006:6006 \
    -v /opt/phoenix/data:/phoenix/data \
    -e PHOENIX_SQL_DATABASE_URL=sqlite:////phoenix/data/phoenix.db \
    -e YOUR_CUSTOM_VAR=value \
    arizephoenix/phoenix:latest
```

### Scaling

For higher loads, consider:

1. **Vertical scaling**: Use larger machine types
2. **Load balancing**: Deploy multiple instances behind a load balancer
3. **Database**: Switch from SQLite to PostgreSQL or MySQL

## Cost Optimization

1. **Auto-shutdown**: Schedule instance shutdown during off-hours
2. **Preemptible instances**: Use `--preemptible` flag for development
3. **Right-sizing**: Monitor resource usage and adjust machine type

### Scheduled Shutdown Example

```bash
# Add to crontab to stop instance at 6 PM weekdays
0 18 * * 1-5 gcloud compute instances stop phoenix-server --zone=us-central1-a
```

## Support

For Phoenix-specific issues, visit:
- [Arize Phoenix GitHub](https://github.com/Arize-ai/phoenix)
- [Arize Phoenix Documentation](https://docs.arize.com/phoenix)

For deployment script issues, please check the troubleshooting section above. 