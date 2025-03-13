#!/bin/bash
# 05c-vault-utils-config.sh
# Configuration functions for Vault deployment

# Function to create Vault configuration
create_vault_config() {
  log "Creating Vault job configuration..."
  
  # Ensure job directory exists
  mkdir -p "${JOB_DIR}"
  
  # Default values if not set in config
  VAULT_HTTP_PORT=${VAULT_HTTP_PORT:-8200}
  VAULT_IMAGE=${VAULT_IMAGE:-"hashicorp/vault:latest"}
  VAULT_CPU=${VAULT_CPU:-500}
  VAULT_MEMORY=${VAULT_MEMORY:-1024}
  VAULT_HOST=${VAULT_HOST:-"vault.${DOMAIN:-homelab.local}"}
  VAULT_DEV_MODE=${VAULT_DEV_MODE:-"false"}
  
  log "Using configuration values:"
  log "- HTTP Port: ${VAULT_HTTP_PORT}"
  log "- Image: ${VAULT_IMAGE}"
  log "- CPU: ${VAULT_CPU}"
  log "- Memory: ${VAULT_MEMORY}"
  log "- Host: ${VAULT_HOST}"
  log "- Dev Mode: ${VAULT_DEV_MODE}"
  
  # Decide on storage and API configurations based on dev_mode
  local storage_config
  local api_config
  local ui_config="ui = true"
  local extra_env=""
  
  if [ "${VAULT_DEV_MODE}" = "true" ]; then
    # Dev mode configuration
    log "Using development mode configuration"
    storage_config="storage \"inmem\" {}"
    api_config="api_addr = \"http://{{ env \"NOMAD_IP_http\" }}:${VAULT_HTTP_PORT}\""
    extra_env="VAULT_DEV_ROOT_TOKEN_ID=root"
    warn "Vault will run in DEVELOPMENT mode - NOT SUITABLE FOR PRODUCTION"
    warn "Dev mode is for testing only and stores data in memory (data will be lost on restart)"
  else
    # Production mode configuration with file storage
    log "Using production mode configuration with file storage"
    storage_config=$(cat <<EOF
storage "file" {
  path = "/vault/data"
}
EOF
)
    api_config="api_addr = \"http://{{ env \"NOMAD_IP_http\" }}:${VAULT_HTTP_PORT}\""
  fi
  
  # Check if Consul is available for service registration
  local service_registration=""
  if curl -s -f "http://localhost:8500/v1/status/leader" &>/dev/null; then
    log "Consul is available - adding service registration configuration"
    service_registration=$(cat <<EOF
service_registration "consul" {
  address = "localhost:8500"
}
EOF
)
  fi
  
  # Create the Vault job configuration
  cat > "${JOB_DIR}/vault.hcl" << EOF
job "vault" {
  datacenters = ["dc1"]
  type = "service"

  group "vault" {
    count = 1

    network {
      port "http" {
        static = ${VAULT_HTTP_PORT}
      }
    }

    volume "vault_data" {
      type = "host"
      read_only = false
      source = "vault_data"
    }

    task "vault" {
      driver = "docker"

      config {
        image = "${VAULT_IMAGE}"
        ports = ["http"]
        
        volumes = [
          "local/vault.hcl:/vault/config/vault.hcl"
        ]
        
        cap_add = [
          "IPC_LOCK"
        ]
      }

      env {
        VAULT_ADDR = "http://\${NOMAD_ADDR_http}"
        ${extra_env}
      }

      volume_mount {
        volume = "vault_data"
        destination = "/vault/data"
        read_only = false
      }

      template {
        data = <<EOF
${storage_config}

listener "tcp" {
  address = "0.0.0.0:${VAULT_HTTP_PORT}"
  tls_disable = true
}

${ui_config}
disable_mlock = true
${api_config}
${service_registration}
EOF
        destination = "local/vault.hcl"
      }

      resources {
        cpu    = ${VAULT_CPU}
        memory = ${VAULT_MEMORY}
      }

      service {
        name = "vault"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.vault.rule=Host(\`${VAULT_HOST}\`)",
          "traefik.http.routers.vault.tls=true",
          "homepage.name=Vault",
          "homepage.icon=vault.png",
          "homepage.group=Security",
          "homepage.description=Secrets Management"
        ]
        
        check {
          name     = "vault_health"
          type     = "http"
          path     = "/v1/sys/health"
          interval = "10s"
          timeout  = "2s"
          
          check_restart {
            limit = 3
            grace = "60s"
            ignore_warnings = true
          }
        }
      }
    }
  }
}
EOF
  
  # Make sure the job file is readable
  chmod 644 "${JOB_DIR}/vault.hcl"
  
  # Create a Vault initialization script file for later use
  mkdir -p "${CONFIG_DIR}/vault"
  
  cat > "${CONFIG_DIR}/vault/init.sh" << 'EOF'
#!/bin/bash
# Vault initialization script

# Get allocation ID for Vault
ALLOC_ID=$(nomad job status -verbose vault | grep "Allocations" -A2 | tail -n1 | awk '{print $1}')

if [ -z "$ALLOC_ID" ]; then
  echo "Error: Could not find Vault allocation"
  exit 1
fi

# Initialize Vault and capture the output
echo "Initializing Vault..."
INIT_OUTPUT=$(nomad alloc exec -task vault $ALLOC_ID vault operator init)

# Save the output to a file
echo "$INIT_OUTPUT" > vault-init.txt
chmod 600 vault-init.txt

echo "Vault has been initialized."
echo "The unseal keys and root token have been saved to vault-init.txt"
echo "IMPORTANT: Keep this file secure! Anyone with these keys can access your Vault."

# Extract unseal keys and root token
UNSEAL_KEYS=$(echo "$INIT_OUTPUT" | grep "Unseal Key" | awk '{print $4}')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep "Root Token" | awk '{print $3}')

# Unseal Vault
echo "Unsealing Vault..."
echo "$UNSEAL_KEYS" | head -n3 | while read -r key; do
  echo "Using unseal key: $key"
  nomad alloc exec -task vault $ALLOC_ID vault operator unseal $key
done

echo "Vault is now initialized and unsealed."
echo "Root Token: $ROOT_TOKEN"
echo "Save this information in a secure location."
EOF
  
  chmod 755 "${CONFIG_DIR}/vault/init.sh"
  
  success "Vault job configuration created"
}