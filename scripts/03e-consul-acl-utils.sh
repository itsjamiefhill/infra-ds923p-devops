#!/bin/bash
# 03e-consul-acl-utils.sh
# ACL utility functions for Consul deployment

# Function to prepare ACL configuration
prepare_consul_acl() {
  log "Preparing Consul ACL configuration..."
  
  # Create directory for ACL configuration
  sudo mkdir -p "${CONFIG_DIR}/consul" 2>/dev/null
  
  # Create ACL configuration file (this is the correct format for Consul ACL config)
  cat > /tmp/acl.json << EOFACL
{
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "enable_token_persistence": true
  }
}
EOFACL

  # Use sudo to copy the file and set permissions
  sudo cp /tmp/acl.json "${CONFIG_DIR}/consul/acl.json"
  sudo chmod 644 "${CONFIG_DIR}/consul/acl.json"
  rm /tmp/acl.json
  
  log "ACL configuration created at ${CONFIG_DIR}/consul/acl.json"
  
  # Create or update the start-consul.sh script to include ACL config
  update_start_script_for_acl
  
  # Create token management script
  create_token_management_script
  
  success "ACL configuration ready"
}

# Function to bootstrap ACL system and create necessary tokens
bootstrap_consul_acl() {
  log "Bootstrapping Consul ACL system..."
  
  # Wait for Consul to be ready
  log "Waiting for Consul to be fully operational..."
  sleep 10
  
  # Check if Consul is running
  local protocol="http"
  local insecure=""
  
  if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
    protocol="https"
    insecure="-k"
  else
    insecure=""
  fi
  
  # Check if Consul is responding
  if ! curl -s ${insecure} ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/status/leader > /dev/null; then
    warn "Consul is not fully operational yet. Waiting longer..."
    sleep 20
    
    if ! curl -s ${insecure} ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/status/leader > /dev/null; then
      error "Consul is not responding. Cannot bootstrap ACL system."
    fi
  fi
  
  log "Consul is responding. Bootstrapping ACL system..."
  
  # Bootstrap ACL system and save the bootstrap token
  BOOTSTRAP_RESULT=$(curl -s ${insecure} -X PUT ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/bootstrap)
  if [ $? -ne 0 ] || [ -z "$BOOTSTRAP_RESULT" ] || [[ "$BOOTSTRAP_RESULT" == *"error"* ]]; then
    warn "Failed to bootstrap ACL system. It might be already bootstrapped."
    
    # Try to get the tokens from the saved file (looking in config dir)
    if [ -f "${PARENT_DIR}/config/consul_tokens.json" ]; then
      log "Found existing ACL tokens in config directory. Using them."
      BOOTSTRAP_TOKEN=$(jq -r '.bootstrap_token' "${PARENT_DIR}/config/consul_tokens.json" 2>/dev/null)
      
      if [ -z "$BOOTSTRAP_TOKEN" ] || [ "$BOOTSTRAP_TOKEN" = "null" ]; then
        warn "Could not retrieve bootstrap token from saved file."
        return 1
      else
        success "Retrieved bootstrap token from saved file."
        
        # Display the bootstrap token during the install process
        echo ""
        echo "================================================================="
        echo "CONSUL BOOTSTRAP TOKEN (ADMIN ACCESS)"
        echo "================================================================="
        echo "Token: ${BOOTSTRAP_TOKEN}"
        echo "================================================================="
        echo ""
      fi
    else
      warn "No saved ACL tokens found. ACL bootstrapping failed."
      return 1
    fi
  else
    BOOTSTRAP_TOKEN=$(echo "$BOOTSTRAP_RESULT" | jq -r '.SecretID')
    
    if [ -z "$BOOTSTRAP_TOKEN" ] || [ "$BOOTSTRAP_TOKEN" = "null" ]; then
      warn "Failed to parse bootstrap token from Consul response."
      log "Consul response: $BOOTSTRAP_RESULT"
      return 1
    else
      log "Successfully bootstrapped ACL system and obtained bootstrap token."
      
      # Display the bootstrap token during the install process
      echo ""
      echo "================================================================="
      echo "CONSUL BOOTSTRAP TOKEN (ADMIN ACCESS)"
      echo "================================================================="
      echo "Token: ${BOOTSTRAP_TOKEN}"
      echo "================================================================="
      echo ""
      
      # Create necessary policies and tokens
      create_service_tokens "$BOOTSTRAP_TOKEN" "$protocol" "$insecure"
    fi
  fi
}

# Function to create service tokens
# Function to create service tokens with modified storage location
create_service_tokens() {
  local BOOTSTRAP_TOKEN="$1"
  local protocol="$2"
  local insecure="$3"
  
  log "Creating service policies and tokens..."
  
  # Create a policy for Nomad
  local NOMAD_POLICY='{
  "Name": "nomad-policy",
  "Description": "Policy for Nomad server to interact with Consul",
  "Rules": "node_prefix \"\" { policy = \"read\" } service_prefix \"\" { policy = \"write\" } agent_prefix \"\" { policy = \"write\" } key_prefix \"nomad/\" { policy = \"write\" }"
}'
  
  # Create the Nomad policy
  log "Creating Nomad policy..."
  local NOMAD_POLICY_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
    -d "$NOMAD_POLICY" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/policy)
  
  # Create a token for Nomad
  log "Creating Nomad token..."
  local NOMAD_TOKEN_CREATE='{
  "Description": "Nomad server token",
  "Policies": [
    {
      "Name": "nomad-policy"
    }
  ]
}'
  
  local NOMAD_TOKEN_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
    -d "$NOMAD_TOKEN_CREATE" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/token)
  
  local NOMAD_TOKEN=$(echo "$NOMAD_TOKEN_RESULT" | jq -r '.SecretID')
  
  if [ -z "$NOMAD_TOKEN" ] || [ "$NOMAD_TOKEN" = "null" ]; then
    warn "Failed to create Nomad token."
    log "Consul response: $NOMAD_TOKEN_RESULT"
    NOMAD_TOKEN="<failed_to_create>"
  else
    log "Successfully created Nomad token."
  fi
  
  # Create a policy for Traefik
  local TRAEFIK_POLICY='{
  "Name": "traefik-policy",
  "Description": "Policy for Traefik to discover services in Consul",
  "Rules": "service_prefix \"\" { policy = \"read\" } node_prefix \"\" { policy = \"read\" } key_prefix \"traefik/\" { policy = \"write\" }"
}'
  
  # Create the Traefik policy
  log "Creating Traefik policy..."
  local TRAEFIK_POLICY_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
    -d "$TRAEFIK_POLICY" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/policy)
  
  # Create a token for Traefik
  log "Creating Traefik token..."
  local TRAEFIK_TOKEN_CREATE='{
  "Description": "Traefik token",
  "Policies": [
    {
      "Name": "traefik-policy"
    }
  ]
}'
  
  local TRAEFIK_TOKEN_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
    -d "$TRAEFIK_TOKEN_CREATE" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/token)
  
  local TRAEFIK_TOKEN=$(echo "$TRAEFIK_TOKEN_RESULT" | jq -r '.SecretID')
  
  if [ -z "$TRAEFIK_TOKEN" ] || [ "$TRAEFIK_TOKEN" = "null" ]; then
    warn "Failed to create Traefik token."
    log "Consul response: $TRAEFIK_TOKEN_RESULT"
    TRAEFIK_TOKEN="<failed_to_create>"
  else
    log "Successfully created Traefik token."
  fi
  
  # Create a policy for Vault
  local VAULT_POLICY='{
  "Name": "vault-policy",
  "Description": "Policy for Vault to interact with Consul",
  "Rules": "key_prefix \"vault/\" { policy = \"write\" } service \"vault\" { policy = \"write\" } node_prefix \"\" { policy = \"read\" } agent_prefix \"\" { policy = \"read\" }"
}'
  
  # Create the Vault policy
  log "Creating Vault policy..."
  local VAULT_POLICY_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
    -d "$VAULT_POLICY" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/policy)
  
  # Create a token for Vault
  log "Creating Vault token..."
  local VAULT_TOKEN_CREATE='{
  "Description": "Vault server token",
  "Policies": [
    {
      "Name": "vault-policy"
    }
  ]
}'
  
  local VAULT_TOKEN_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
    -d "$VAULT_TOKEN_CREATE" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/token)
  
  local VAULT_TOKEN=$(echo "$VAULT_TOKEN_RESULT" | jq -r '.SecretID')
  
  if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" = "null" ]; then
    warn "Failed to create Vault token."
    log "Consul response: $VAULT_TOKEN_RESULT"
    VAULT_TOKEN="<failed_to_create>"
  else
    log "Successfully created Vault token."
  fi
  
  # Create a policy for DNS access (anonymous)
  local AGENT_POLICY='{
  "Name": "agent-policy",
  "Description": "Policy for anonymous DNS access",
  "Rules": "service_prefix \"\" { policy = \"read\" } node_prefix \"\" { policy = \"read\" }"
}'
  
  # Create the agent policy
  log "Creating agent policy for DNS..."
  local AGENT_POLICY_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
    -d "$AGENT_POLICY" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/policy)
  
  # Update anonymous token with this policy
  log "Updating anonymous token with DNS read access..."
  local ANON_TOKEN_UPDATE='{
  "Description": "Anonymous Token - DNS Access",
  "Policies": [
    {
      "Name": "agent-policy"
    }
  ]
}'
  
  local ANON_TOKEN_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
    -d "$ANON_TOKEN_UPDATE" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/token/00000000-0000-0000-0000-000000000002)
  
  # Save the tokens to a file in the CONFIG_DIR instead of secrets directory
  log "Saving tokens to config directory..."
  
  # Create token file in temp directory first
  cat > /tmp/consul_tokens.json << EOFJSON
{
  "bootstrap_token": "$BOOTSTRAP_TOKEN",
  "nomad_token": "$NOMAD_TOKEN",
  "traefik_token": "$TRAEFIK_TOKEN",
  "vault_token": "$VAULT_TOKEN"
}
EOFJSON
  
  # Use sudo to copy the file and set permissions
  # Instead of saving to ${PARENT_DIR}/secrets/, we save directly to ${PARENT_DIR}/config/
  sudo mkdir -p "${PARENT_DIR}/config" 2>/dev/null
  sudo cp /tmp/consul_tokens.json "${PARENT_DIR}/config/consul_tokens.json"
  sudo chmod 644 "${PARENT_DIR}/config/consul_tokens.json"  # More permissive since it's in the config dir
  rm /tmp/consul_tokens.json
  
  # Also create consul_tokens.conf with environment variables for easy sourcing
  log "Creating token configuration file for subsequent installation steps..."
  
  cat > /tmp/consul_tokens.conf << EOFTOKENS
# Consul ACL tokens for platform components
# Generated on $(date)
# This file is automatically sourced by subsequent installation steps

# Consul bootstrap token (admin access)
CONSUL_BOOTSTRAP_TOKEN="$BOOTSTRAP_TOKEN"

# Service-specific tokens
CONSUL_NOMAD_TOKEN="$NOMAD_TOKEN"
CONSUL_TRAEFIK_TOKEN="$TRAEFIK_TOKEN"
CONSUL_VAULT_TOKEN="$VAULT_TOKEN"
EOFTOKENS

  sudo cp /tmp/consul_tokens.conf "${PARENT_DIR}/config/consul_tokens.conf"
  sudo chmod 644 "${PARENT_DIR}/config/consul_tokens.conf"
  rm /tmp/consul_tokens.conf
  
  success "Created and saved all service tokens to ${PARENT_DIR}/config directory"
}

clean_up_token_files() {
  log "Cleaning up any token files in Consul config directory..."
  
  # Check if there's an acl_tokens.json file in the Consul config dir
  if [ -f "${CONFIG_DIR}/consul/acl_tokens.json" ]; then
    log "Found acl_tokens.json in Consul config directory. Removing it..."
    sudo rm "${CONFIG_DIR}/consul/acl_tokens.json"
  fi
  
  # Check if there's a consul_tokens.json file in the Consul config dir
  if [ -f "${CONFIG_DIR}/consul/consul_tokens.json" ]; then
    log "Found consul_tokens.json in Consul config directory. Removing it..."
    sudo rm "${CONFIG_DIR}/consul/consul_tokens.json"
  fi
  
  # Create placeholder in case the file doesn't exist yet but will be needed by other modules
  if [ ! -f "${PARENT_DIR}/config/consul_tokens.conf" ]; then
    log "Creating placeholder token configuration file..."
    
    mkdir -p "${PARENT_DIR}/config" 2>/dev/null
    cat > "${PARENT_DIR}/config/consul_tokens.conf" << EOFCONF
# Consul ACL tokens for platform components (placeholder)
# This file will be populated when Consul ACL is bootstrapped

# Consul bootstrap token (admin access)
CONSUL_BOOTSTRAP_TOKEN="not_yet_created"

# Service-specific tokens
CONSUL_NOMAD_TOKEN="not_yet_created"
CONSUL_TRAEFIK_TOKEN="not_yet_created"
CONSUL_VAULT_TOKEN="not_yet_created"
EOFCONF
    
    chmod 644 "${PARENT_DIR}/config/consul_tokens.conf"
  fi
  
  success "Consul config directory cleaned up"
}

# Function to create token management script
create_token_management_script() {
  log "Creating token management script..."
  
  mkdir -p "${PARENT_DIR}/bin" 2>/dev/null
  
  # Use a different heredoc delimiter to avoid conflicts
  cat > "${PARENT_DIR}/bin/consul-tokens.sh" << 'EOFSCRIPT'
#!/bin/bash
# consul-tokens.sh - Helper script to manage Consul ACL tokens

# Determine script and parent directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PARENT_DIR}/config"

# Source configuration
if [ -f "${PARENT_DIR}/config/default.conf" ]; then
    source "${PARENT_DIR}/config/default.conf"
fi

if [ -f "${PARENT_DIR}/config/custom.conf" ]; then
    source "${PARENT_DIR}/config/custom.conf"
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Token file location
TOKEN_FILE="${PARENT_DIR}/secrets/consul_tokens.json"

# Set default values if not defined
CONSUL_HTTP_PORT=${CONSUL_HTTP_PORT:-8500}
CONSUL_ENABLE_SSL=${CONSUL_ENABLE_SSL:-false}
CONFIG_DIR=${CONFIG_DIR:-"${PARENT_DIR}/config"}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq to use this script.${NC}"
    exit 1
fi

# Display usage information
usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  show                Show all saved tokens"
    echo "  list                List all tokens in Consul"
    echo "  policies            List all policies in Consul"
    echo "  create NAME         Create a new token for a service"
    echo "  help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 show             # Display all saved tokens"
    echo "  $0 create myapp     # Create a token for 'myapp' service"
}

# Function to check if Consul is running
check_consul() {
    local protocol="http"
    local insecure=""
    
    if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
        protocol="https"
        insecure="-k"
    fi
    
    if ! curl -s ${insecure} ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/status/leader > /dev/null; then
        echo -e "${RED}Error: Consul is not running or not accessible. Please start Consul first.${NC}"
        exit 1
    fi
}

# Function to get bootstrap token
get_bootstrap_token() {
    if [ ! -f "${TOKEN_FILE}" ]; then
        echo -e "${RED}Error: ACL tokens file not found at ${TOKEN_FILE}${NC}"
        exit 1
    fi
    
    BOOTSTRAP_TOKEN=$(jq -r '.bootstrap_token // ""' "${TOKEN_FILE}")
    
    if [ -z "$BOOTSTRAP_TOKEN" ] || [ "$BOOTSTRAP_TOKEN" = "null" ]; then
        echo -e "${RED}Error: Bootstrap token not found in tokens file${NC}"
        exit 1
    fi
}

# Function to display all saved tokens
show_tokens() {
    if [ ! -f "${TOKEN_FILE}" ]; then
        echo -e "${RED}Error: ACL tokens file not found at ${TOKEN_FILE}${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}======== Consul ACL Tokens ========${NC}"
    jq -r 'to_entries | .[] | "Service: \(.key | sub("_token$"; ""))\nToken: \(.value)"' "${TOKEN_FILE}" | \
    while IFS= read -r line; do
        if [[ $line == Token:* ]]; then
            echo -e "Token: ${YELLOW}${line#Token: }${NC}"
        else
            echo -e "$line"
        fi
        # Add a newline after each token
        if [[ $line == Token:* ]]; then
            echo ""
        fi
    done
    echo -e "${BLUE}=================================${NC}"
    
    # Print usage example
    echo -e "\nTo use these tokens in your configurations:"
    echo -e "For environment variables: ${YELLOW}export CONSUL_HTTP_TOKEN=<token>${NC}"
    echo -e "For API requests: ${YELLOW}curl -H \"X-Consul-Token: <token>\" http://localhost:${CONSUL_HTTP_PORT}/v1/...${NC}"
}

# Function to list all tokens in Consul
list_tokens() {
    check_consul
    get_bootstrap_token
    
    local protocol="http"
    local insecure=""
    
    if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
        protocol="https"
        insecure="-k"
    fi
    
    echo -e "${BLUE}Querying Consul for all tokens...${NC}"
    local TOKENS_RESULT=$(curl -s ${insecure} -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
        ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/tokens)
    
    echo -e "${BLUE}======== Consul ACL Tokens ========${NC}"
    echo "$TOKENS_RESULT" | jq -r '.[] | "ID: \(.AccessorID)\nName: \(.Description)\nType: \(.Type)\nCreated: \(.CreateTime)\n"'
    echo -e "${BLUE}=================================${NC}"
}

# Function to list all policies in Consul
list_policies() {
    check_consul
    get_bootstrap_token
    
    local protocol="http"
    local insecure=""
    
    if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
        protocol="https"
        insecure="-k"
    fi
    
    echo -e "${BLUE}Querying Consul for all policies...${NC}"
    local POLICIES_RESULT=$(curl -s ${insecure} -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
        ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/policies)
    
    echo -e "${BLUE}======== Consul ACL Policies ========${NC}"
    echo "$POLICIES_RESULT" | jq -r '.[] | "ID: \(.ID)\nName: \(.Name)\nDescription: \(.Description)\n"'
    echo -e "${BLUE}=================================${NC}"
}

# Function to create a token for a service
create_token() {
    check_consul
    get_bootstrap_token
    
    local SERVICE_NAME="$1"
    if [ -z "$SERVICE_NAME" ]; then
        echo -e "${RED}Error: Service name is required${NC}"
        echo "Usage: $0 create <service-name>"
        exit 1
    fi
    
    # Format policy name and description
    local POLICY_NAME="${SERVICE_NAME}-policy"
    local TOKEN_DESC="${SERVICE_NAME} service token"
    
    echo -e "${BLUE}Creating policy and token for service: ${YELLOW}${SERVICE_NAME}${NC}"
    
    local protocol="http"
    local insecure=""
    
    if [ "${CONSUL_ENABLE_SSL:-false}" = "true" ]; then
        protocol="https"
        insecure="-k"
    fi
    
    # Create a reasonable default policy for the service
    local SERVICE_POLICY='{
  "Name": "'"$POLICY_NAME"'",
  "Description": "Policy for '"$SERVICE_NAME"' service",
  "Rules": "service \"'"$SERVICE_NAME"'\" { policy = \"write\" } service_prefix \"\" { policy = \"read\" } node_prefix \"\" { policy = \"read\" } key_prefix \"'"$SERVICE_NAME/"'\" { policy = \"write\" }"
}'
    
    # Create the service policy
    echo -e "${BLUE}Creating policy...${NC}"
    local POLICY_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
        -d "$SERVICE_POLICY" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/policy)
    
    if [[ "$POLICY_RESULT" == *"error"* ]]; then
        echo -e "${RED}Error creating policy:${NC}"
        echo "$POLICY_RESULT" | jq -r '.error'
        exit 1
    fi
    
    # Create a token for the service
    echo -e "${BLUE}Creating token...${NC}"
    local TOKEN_CREATE='{
  "Description": "'"$TOKEN_DESC"'",
  "Policies": [
    {
      "Name": "'"$POLICY_NAME"'"
    }
  ]
}'
    
    local TOKEN_RESULT=$(curl -s ${insecure} -X PUT -H "X-Consul-Token: $BOOTSTRAP_TOKEN" \
        -d "$TOKEN_CREATE" ${protocol}://localhost:${CONSUL_HTTP_PORT}/v1/acl/token)
    
    if [[ "$TOKEN_RESULT" == *"error"* ]]; then
        echo -e "${RED}Error creating token:${NC}"
        echo "$TOKEN_RESULT" | jq -r '.error'
        exit 1
    fi
    
    local SERVICE_TOKEN=$(echo "$TOKEN_RESULT" | jq -r '.SecretID')
    
    # Update the tokens file with the new token
    echo -e "${BLUE}Updating tokens file...${NC}"
    local TEMP_FILE=$(mktemp)
    jq --arg key "${SERVICE_NAME}_token" --arg value "$SERVICE_TOKEN" '. + {($key): $value}' \
        "${TOKEN_FILE}" > "$TEMP_FILE"
    
    sudo cp "$TEMP_FILE" "${TOKEN_FILE}"
    sudo chmod 600 "${TOKEN_FILE}"
    rm "$TEMP_FILE"
    
    # Update the platform config file
    if [ -f "${PARENT_DIR}/config/consul_tokens.conf" ]; then
        echo -e "${BLUE}Updating platform config...${NC}"
        echo "CONSUL_${SERVICE_NAME^^}_TOKEN=\"$SERVICE_TOKEN\"" | sudo tee -a "${PARENT_DIR}/config/consul_tokens.conf" > /dev/null
    fi
    
    echo -e "\n${GREEN}======== New Token Created ========${NC}"
    echo -e "Service: ${YELLOW}${SERVICE_NAME}${NC}"
    echo -e "Policy: ${YELLOW}${POLICY_NAME}${NC}"
    echo -e "Token: ${YELLOW}${SERVICE_TOKEN}${NC}"
    echo -e "${GREEN}=================================${NC}"
    
    echo -e "\nTo use this token in your service configuration:"
    echo -e "For environment variables: ${YELLOW}export CONSUL_HTTP_TOKEN=${SERVICE_TOKEN}${NC}"
    echo -e "For API requests: ${YELLOW}curl -H \"X-Consul-Token: ${SERVICE_TOKEN}\" http://localhost:${CONSUL_HTTP_PORT}/v1/...${NC}"
}

# Main function
main() {
    case "$1" in
        show)
            show_tokens
            ;;
        list)
            list_tokens
            ;;
        policies)
            list_policies
            ;;
        create)
            create_token "$2"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            usage
            ;;
    esac
}

# Run main with all arguments
main "$@"
EOFSCRIPT

  chmod +x "${PARENT_DIR}/bin/consul-tokens.sh"
  
  log "Token management script created at ${PARENT_DIR}/bin/consul-tokens.sh"
}