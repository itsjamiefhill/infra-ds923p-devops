#!/bin/bash
# 03-deploy-consul.sh
# Deploys Consul service discovery as a Nomad job

set -e

# Script directory and import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Load all utility scripts
if [ -f "${SCRIPT_DIR}/03a-consul-utils.sh" ]; then
    source "${SCRIPT_DIR}/03a-consul-utils.sh"
else
    echo "Error: Could not find 03a-consul-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/03b-consul-utils.sh" ]; then
    source "${SCRIPT_DIR}/03b-consul-utils.sh"
else
    echo "Error: Could not find 03b-consul-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/03c-consul-utils.sh" ]; then
    source "${SCRIPT_DIR}/03c-consul-utils.sh"
else
    echo "Error: Could not find 03c-consul-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/03d-consul-utils.sh" ]; then
    source "${SCRIPT_DIR}/03d-consul-utils.sh"
else
    echo "Error: Could not find 03d-consul-utils.sh"
    exit 1
fi

# Clear previous configuration to avoid conflicts
unset CONSUL_VERSION CONSUL_HTTP_PORT CONSUL_DNS_PORT CONSUL_CPU CONSUL_MEMORY CONSUL_HOST
unset CONSUL_BIND_ADDR CONSUL_ADVERTISE_ADDR CONSUL_USE_DOCKER DNS_USE_HOSTS_FILE DNS_USE_DNSMASQ
unset CONSUL_ENABLE_SSL

# Source configuration files
source "${PARENT_DIR}/config/default.conf"

# If custom config exists, load it
if [ -f "${PARENT_DIR}/config/custom.conf" ]; then
    source "${PARENT_DIR}/config/custom.conf"
fi

# Set up logging
LOGS_DIR=${LOG_DIR:-"${PARENT_DIR}/logs"}
LOG_FILE="${LOGS_DIR}/consul_deploy.log"

# Ensure logs directory exists
mkdir -p "${LOGS_DIR}"

# Set default values if not defined in config
CONSUL_VERSION=${CONSUL_VERSION:-"1.15.4"}
CONSUL_HTTP_PORT=${CONSUL_HTTP_PORT:-8500}
CONSUL_DNS_PORT=${CONSUL_DNS_PORT:-8600}
CONSUL_CPU=${CONSUL_CPU:-500}
CONSUL_MEMORY=${CONSUL_MEMORY:-512}
CONSUL_HOST=${CONSUL_HOST:-"consul.${DOMAIN:-homelab.local}"}
CONSUL_USE_DOCKER=${CONSUL_USE_DOCKER:-false}
CONSUL_BIND_ADDR=${CONSUL_BIND_ADDR:-""}
CONSUL_ADVERTISE_ADDR=${CONSUL_ADVERTISE_ADDR:-""}
DNS_USE_HOSTS_FILE=${DNS_USE_HOSTS_FILE:-true}
DNS_USE_DNSMASQ=${DNS_USE_DNSMASQ:-false}
DOMAIN=${DOMAIN:-"homelab.local"}
CONSUL_ENABLE_SSL=${CONSUL_ENABLE_SSL:-false}

# Print loaded configuration for debugging
log "Loaded configuration:"
log "DATA_DIR=${DATA_DIR}"
log "CONFIG_DIR=${CONFIG_DIR}"
log "JOB_DIR=${JOB_DIR}"
log "DOMAIN=${DOMAIN}"
log "CONSUL_VERSION=${CONSUL_VERSION}"
log "CONSUL_HTTP_PORT=${CONSUL_HTTP_PORT}"
log "CONSUL_DNS_PORT=${CONSUL_DNS_PORT}"
log "CONSUL_HOST=${CONSUL_HOST}"
log "CONSUL_USE_DOCKER=${CONSUL_USE_DOCKER}"
log "CONSUL_ENABLE_SSL=${CONSUL_ENABLE_SSL}"
log "NOMAD_ADDR=${NOMAD_ADDR}"

# Main function
main() {
  log "Starting Consul deployment..."
  
  # Step 1: Setup Nomad authentication
  setup_nomad_auth
  
  # Step 1.5: Setup Nomad SSL environment
  setup_nomad_ssl
  
  # Step 2: Check Docker permissions
  check_docker_permissions
  
  # Step 3: Prepare the data directory
  prepare_consul_directory
  
  # Step 3.5: Prepare SSL certificates for Consul if enabled
  if [ "${CONSUL_ENABLE_SSL}" = "true" ]; then
    prepare_consul_ssl
  fi
  
  # Step 4: Create the job configuration
  create_consul_job
  
  # Step 5: Create helper scripts
  create_helper_scripts
  
  # Step 6: Deploy Consul based on configuration
  if [ "$CONSUL_USE_DOCKER" = true ]; then
    deploy_consul_docker
  else
    # Try Nomad deployment first
    if deploy_consul_nomad; then
      log "Consul deployed successfully with Nomad"
    else
      warn "Nomad deployment failed. Creating fallback Docker deployment scripts."
      create_docker_fallback
      echo -e "${YELLOW}Would you like to run the Docker fallback script now? [y/N]${NC}"
      read -r run_docker
      if [[ "$run_docker" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        "${PARENT_DIR}/bin/consul-docker-run.sh"
      else
        warn "Consul deployment incomplete. You can run the fallback script manually later with: ${PARENT_DIR}/bin/consul-docker-run.sh"
      fi
    fi
  fi
  
  # Step 7: Setup Consul DNS integration
  setup_consul_dns
  
  # Step 8: Add Consul host entry to /etc/hosts in non-interactive mode
  SYNOLOGY_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
  
  if ! grep -q "${CONSUL_HOST}" /etc/hosts; then
    log "Adding Consul host entry to /etc/hosts in non-interactive mode..."
    echo "${SYNOLOGY_IP}  ${CONSUL_HOST}" | sudo tee -a /etc/hosts > /dev/null
    success "Hosts file updated automatically for ${CONSUL_HOST}"
  else
    log "Consul host entry already exists in hosts file"
  fi
  
  # Step 9: Show access information
  show_access_info
  
  log "Consul setup completed. If you encounter issues, use the troubleshooting scripts."
  success "Consul setup process finished"
}

# Execute main function
main "$@"