#!/bin/bash
# 03-deploy-consul.sh
# Deploys Consul service discovery using direct Docker commands for Synology with sudo

set -e

# Script directory and import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "${PARENT_DIR}/config/default.conf"

# If custom config exists, load it
if [ -f "${PARENT_DIR}/config/custom.conf" ]; then
    source "${PARENT_DIR}/config/custom.conf"
fi

# Set default values if not defined in config
CONSUL_VERSION=${CONSUL_VERSION:-"1.15.4"}
CONSUL_HTTP_PORT=${CONSUL_HTTP_PORT:-8500}
CONSUL_DNS_PORT=${CONSUL_DNS_PORT:-8600}
CONSUL_CPU=${CONSUL_CPU:-500}
CONSUL_MEMORY=${CONSUL_MEMORY:-512}
CONSUL_HOST=${CONSUL_HOST:-"consul.homelab.local"}
CONSUL_USE_DOCKER=${CONSUL_USE_DOCKER:-true}
CONSUL_BIND_ADDR=${CONSUL_BIND_ADDR:-""}
CONSUL_ADVERTISE_ADDR=${CONSUL_ADVERTISE_ADDR:-""}
DNS_USE_HOSTS_FILE=${DNS_USE_HOSTS_FILE:-true}
DNS_USE_DNSMASQ=${DNS_USE_DNSMASQ:-false}

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display status messages
log() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  exit 1
}

# Get the Synology's primary IP address
get_primary_ip() {
  # Try to determine the primary IP address
  PRIMARY_IP=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null)
  
  # If that doesn't work, try an alternative method
  if [ -z "$PRIMARY_IP" ]; then
    PRIMARY_IP=$(hostname -I | awk '{print $1}')
  fi
  
  # If we still don't have an IP, ask the user
  if [ -z "$PRIMARY_IP" ]; then
    log "Could not automatically determine IP address."
    echo -e "${YELLOW}"
    read -p "Please enter the IP address that Consul should use: " PRIMARY_IP
    echo -e "${NC}"
    
    if [ -z "$PRIMARY_IP" ]; then
      error "No IP address provided. Cannot continue."
    fi
  fi
  
  # Only return the IP address itself
  echo "$PRIMARY_IP"
}

# Deploy Consul using direct Docker command for Synology with sudo
deploy_consul_docker() {
  log "Deploying Consul using direct Docker command for Synology..."
  
  # Get the primary IP address if not explicitly set in config
  if [ -z "$CONSUL_BIND_ADDR" ] || [ -z "$CONSUL_ADVERTISE_ADDR" ]; then
    PRIMARY_IP=$(get_primary_ip)
    CONSUL_BIND_ADDR=${CONSUL_BIND_ADDR:-$PRIMARY_IP}
    CONSUL_ADVERTISE_ADDR=${CONSUL_ADVERTISE_ADDR:-$PRIMARY_IP}
  fi
  
  log "Using IP address: ${CONSUL_BIND_ADDR} for Consul"
  
  # Check if Docker is available
  if ! command -v docker &>/dev/null; then
    error "Docker is not available. Please install Docker first."
  fi
  
  # Stop and remove any existing Consul container
  log "Stopping any existing Consul container..."
  sudo docker stop consul 2>/dev/null || true
  sudo docker rm consul 2>/dev/null || true
  
  # Create startup script for Consul
  log "Creating startup script for Consul..."
  
  mkdir -p ${PARENT_DIR}/bin
  cat > ${PARENT_DIR}/bin/start-consul.sh << EOF
#!/bin/bash
# Start Consul container

# Get the primary IP if not passed
if [ -z "\$PRIMARY_IP" ]; then
  PRIMARY_IP=\$(ip route get 1 | awk '{print \$7;exit}' 2>/dev/null || hostname -I | awk '{print \$1}')
  if [ -z "\$PRIMARY_IP" ]; then
    echo "Error: Could not determine primary IP address"
    exit 1
  fi
fi

sudo docker stop consul 2>/dev/null || true
sudo docker rm consul 2>/dev/null || true
sudo docker run -d --name consul \\
  --restart always \\
  --network host \\
  -v ${DATA_DIR}/consul_data:/consul/data \\
  hashicorp/consul:${CONSUL_VERSION} \\
  agent -server -bootstrap \\
  -bind=${CONSUL_BIND_ADDR} \\
  -advertise=${CONSUL_ADVERTISE_ADDR} \\
  -client=0.0.0.0 \\
  -ui
EOF
  
  chmod +x ${PARENT_DIR}/bin/start-consul.sh
  
  # Create stop script for Consul
  cat > ${PARENT_DIR}/bin/stop-consul.sh << EOF
#!/bin/bash
# Stop Consul container
sudo docker stop consul
sudo docker rm consul
EOF
  
  chmod +x ${PARENT_DIR}/bin/stop-consul.sh
  
  # Run the start script
  log "Starting Consul container..."
  PRIMARY_IP="${CONSUL_BIND_ADDR}" sudo ${PARENT_DIR}/bin/start-consul.sh
  
  # Wait for Consul to be ready
  log "Waiting for Consul to be ready..."
  sleep 10
  
  # Check if Consul is running
  if ! curl -s http://localhost:${CONSUL_HTTP_PORT}/v1/status/leader > /dev/null; then
    warn "Consul might not be fully operational yet. Please check status manually with: sudo docker logs consul"
    if ! sudo docker ps | grep -q "consul.*Up"; then
      log "Consul container is not running. Checking logs:"
      sudo docker logs consul
      warn "Please fix the issues and restart the container manually with: sudo ${PARENT_DIR}/bin/start-consul.sh"
    fi
  else
    success "Consul is running and responding to requests"
  fi

  # Create a nomad job reference file for uninstall purposes
  mkdir -p $JOB_DIR
  cat > $JOB_DIR/consul.reference << EOF
# Note: Consul was deployed directly as a Docker container
# To restart: sudo ${PARENT_DIR}/bin/stop-consul.sh && sudo ${PARENT_DIR}/bin/start-consul.sh
# To stop: sudo ${PARENT_DIR}/bin/stop-consul.sh
# To view logs: sudo docker logs consul
# Container name: consul
# IP address: ${CONSUL_BIND_ADDR}
EOF

  success "Consul deployment completed"
  
  # Create instructions to set up automatic startup on Synology
  log "======================================================================================"
  log "To make Consul start automatically when your Synology boots:"
  log "1. Go to DSM > Control Panel > Task Scheduler"
  log "2. Create a new 'Triggered Task' > 'User-defined script'"
  log "3. Set the following properties:"
  log "   - Event: Boot-up"
  log "   - Task: ConsulAutostart"
  log "   - User: root (required for Docker permissions)"
  log "   - Command: ${PARENT_DIR}/bin/start-consul.sh"
  log "4. Save the task"
  log "======================================================================================"
  
  # Output information about accessing Consul
  log "======================================================================================"
  log "Consul is now available at:"
  log "- UI: http://localhost:${CONSUL_HTTP_PORT}/ui/"
  log "- API: http://localhost:${CONSUL_HTTP_PORT}/v1/"
  log "- DNS: localhost:${CONSUL_DNS_PORT} (for .consul domains)"
  log "From other machines, replace 'localhost' with '${CONSUL_BIND_ADDR}'"
  log "======================================================================================"
}

# Deploy Consul as a Nomad job (legacy method)
deploy_consul_nomad() {
  log "Deploying Consul as a Nomad job..."
  
  # This function is preserved for legacy purposes, but not recommended on Synology
  warn "Deploying Consul as a Nomad job is not recommended on Synology due to networking limitations."
  warn "Consider setting CONSUL_USE_DOCKER=true in your configuration."
  
  # Generate job file
  # ... (code for Nomad job deployment, if needed)
  
  error "Nomad-based Consul deployment is not implemented in this version."
}

# Setup Consul DNS Integration with Synology
setup_consul_dns() {
  log "Setting up Consul DNS integration with Synology..."
  
  # Get the primary IP address if not set
  if [ -z "$CONSUL_BIND_ADDR" ]; then
    CONSUL_BIND_ADDR=$(get_primary_ip)
  fi
  
  # Add consul.service.consul to hosts file if enabled
  if [ "$DNS_USE_HOSTS_FILE" = true ]; then
    log "Adding consul.service.consul to /etc/hosts file..."
    # Check if entry already exists and remove it to avoid duplicates
    sudo sed -i '/consul\.service\.consul/d' /etc/hosts
    # Add the new entry
    echo "${CONSUL_BIND_ADDR} consul.service.consul" | sudo tee -a /etc/hosts > /dev/null
    
    # Create a backup of the modified hosts file to the config directory
    sudo cp /etc/hosts ${CONFIG_DIR}/hosts.backup
    
    log "Added hosts file entry: ${CONSUL_BIND_ADDR} consul.service.consul"
  fi
  
  # Attempt dnsmasq configuration if enabled
  if [ "$DNS_USE_DNSMASQ" = true ]; then
    log "Attempting to configure dnsmasq for Consul DNS..."
    
    # Check if dnsmasq exists
    if command -v dnsmasq &>/dev/null; then
      log "dnsmasq found, attempting to configure..."
      # Create directory for dnsmasq config if it doesn't exist
      sudo mkdir -p /etc/dnsmasq.conf.d
      
      # Create or update the Consul DNS configuration
      echo "server=/consul/127.0.0.1#${CONSUL_DNS_PORT}" | sudo tee /etc/dnsmasq.conf.d/10-consul > /dev/null
      
      # Backup the configuration to our platform directory for restoration after DSM updates
      cp /etc/dnsmasq.conf.d/10-consul ${CONFIG_DIR}/10-consul 2>/dev/null || sudo cp /etc/dnsmasq.conf.d/10-consul ${CONFIG_DIR}/10-consul
      
      # Attempt to restart dnsmasq (may fail on some Synology models)
      if command -v systemctl &>/dev/null; then
        sudo systemctl restart dnsmasq || warn "Failed to restart dnsmasq service. Using hosts file for DNS resolution."
      else
        warn "systemctl not found. Using hosts file for DNS resolution."
      fi
    else
      log "dnsmasq not found. Using hosts file for DNS resolution."
    fi
  fi
  
  # Test DNS resolution
  log "Testing DNS resolution for consul.service.consul..."
  if ping -c 1 consul.service.consul &>/dev/null; then
    success "Consul DNS integration configured successfully via hosts file"
  else
    warn "Consul DNS integration might not be working properly. Please check manually."
  fi
  
  log "For full DNS integration throughout your network, consider adding DNS entries"
  log "in your router to forward .consul domains to ${CONSUL_BIND_ADDR}"
}

# Main function
main() {
  log "Starting Consul deployment..."
  
  # Check if Consul data directory exists, create if not
  if [ ! -d "${DATA_DIR}/consul_data" ]; then
    log "Creating Consul data directory..."
    mkdir -p "${DATA_DIR}/consul_data"
    sudo chmod 777 "${DATA_DIR}/consul_data"
    success "Consul data directory created"
  fi
  
  # Deploy Consul using the configured method
  if [ "$CONSUL_USE_DOCKER" = true ]; then
    deploy_consul_docker
  else
    deploy_consul_nomad
  fi
  
  # Setup Consul DNS integration
  setup_consul_dns
  
  success "Consul setup completed"
}

# Execute main function
main "$@"