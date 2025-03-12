#!/bin/bash
# 04-deploy-traefik.sh
# Deploys Traefik as a reverse proxy with TLS support

set -e

# Script directory and import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Load all utility scripts
if [ -f "${SCRIPT_DIR}/04a-traefik-utils.sh" ]; then
    source "${SCRIPT_DIR}/04a-traefik-utils.sh"
else
    echo "Error: Could not find 04a-traefik-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/04b-traefik-utils.sh" ]; then
    source "${SCRIPT_DIR}/04b-traefik-utils.sh"
else
    echo "Error: Could not find 04b-traefik-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/04c-traefik-utils.sh" ]; then
    source "${SCRIPT_DIR}/04c-traefik-utils.sh"
else
    echo "Error: Could not find 04c-traefik-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/04d-traefik-utils.sh" ]; then
    source "${SCRIPT_DIR}/04d-traefik-utils.sh"
else
    echo "Error: Could not find 04d-traefik-utils.sh"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/04e-traefik-utils.sh" ]; then
    source "${SCRIPT_DIR}/04e-traefik-utils.sh"
else
    echo "Error: Could not find 04e-traefik-utils.sh"
    exit 1
fi

# Clear previous configuration to avoid conflicts
unset TRAEFIK_VERSION TRAEFIK_HTTP_PORT TRAEFIK_HTTPS_PORT TRAEFIK_ADMIN_PORT
unset TRAEFIK_CPU TRAEFIK_MEMORY TRAEFIK_HOST WILDCARD_CERT_PATH WILDCARD_KEY_PATH

# Source configuration files
source "${PARENT_DIR}/config/default.conf"

# If custom config exists, load it
if [ -f "${PARENT_DIR}/config/custom.conf" ]; then
    source "${PARENT_DIR}/config/custom.conf"
fi

# Set up logging
LOGS_DIR=${LOG_DIR:-"${PARENT_DIR}/logs"}
LOG_FILE="${LOGS_DIR}/traefik_deploy.log"

# Ensure logs directory exists
mkdir -p "${LOGS_DIR}"

# Print loaded configuration for debugging
log "Loaded configuration:"
log "DATA_DIR=${DATA_DIR}"
log "CONFIG_DIR=${CONFIG_DIR}"
log "JOB_DIR=${JOB_DIR}"
log "DOMAIN=${DOMAIN}"
log "TRAEFIK_VERSION=${TRAEFIK_VERSION}"
log "TRAEFIK_HTTP_PORT=${TRAEFIK_HTTP_PORT}"
log "TRAEFIK_HTTPS_PORT=${TRAEFIK_HTTPS_PORT}"
log "TRAEFIK_ADMIN_PORT=${TRAEFIK_ADMIN_PORT}"
log "WILDCARD_CERT_PATH=${WILDCARD_CERT_PATH}"
log "WILDCARD_KEY_PATH=${WILDCARD_KEY_PATH}"
log "NOMAD_ADDR=${NOMAD_ADDR}"

# Main function
main() {
    log "Starting Traefik deployment..."
    
    # Step 1: Setup Nomad authentication
    setup_nomad_auth
    
    # Step 2: Setup wildcard certificates
    setup_certificates
    
    # Step 3: Check port availability
    check_port_availability
    
    # Step 4: Check Docker permissions
    check_docker_permissions
    
    # Step 5: Create Traefik configuration
    create_traefik_config
    
    # Step 6: Create helper scripts
    create_helper_scripts
    
    # Step 7: Deploy Traefik job
    deploy_traefik
    
    # Step 8: Update hosts file in non-interactive mode
    TRAEFIK_HOST=${TRAEFIK_HOST:-"traefik.${DOMAIN:-homelab.local}"}
    SYNOLOGY_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    
    if ! grep -q "${TRAEFIK_HOST}" /etc/hosts; then
        log "Adding Traefik host entry to /etc/hosts in non-interactive mode..."
        echo "${SYNOLOGY_IP}  ${TRAEFIK_HOST}" | sudo tee -a /etc/hosts > /dev/null
        success "Hosts file updated automatically for ${TRAEFIK_HOST}"
    else
        log "Traefik host entry already exists in hosts file"
    fi
    
    # Step 9: Show access information
    show_access_info
    
    log "Traefik setup completed. If you encounter issues, use the troubleshooting scripts."
    success "Traefik setup process finished"
}

# Execute main function
main "$@"