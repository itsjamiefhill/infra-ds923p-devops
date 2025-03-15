#!/bin/bash
# 02-configure-volumes.sh
# Creates Nomad volume configurations with mount directive for Synology compatibility

set -e

# Script directory and import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PARENT_DIR}/logs"

source "${PARENT_DIR}/config/default.conf"

# If custom config exists, load it
if [ -f "${PARENT_DIR}/config/custom.conf" ]; then
    source "${PARENT_DIR}/config/custom.conf"
fi

# Use LOG_DIR from configuration
LOG_DIR=${LOG_DIR:-"${PARENT_DIR}/logs"}

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display status messages
log() {
  echo -e "${BLUE}[INFO]${NC} $1"
  echo "[INFO] $1" >> "${LOG_DIR}/install.log"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  echo "[SUCCESS] $1" >> "${LOG_DIR}/install.log"
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  echo "[WARNING] $1" >> "${LOG_DIR}/install.log"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  echo "[ERROR] $1" >> "${LOG_DIR}/install.log"
  exit 1
}

# Check Nomad capabilities
check_nomad_capabilities() {
  log "Checking Nomad capabilities..."
  
  # Check Nomad version
  NOMAD_VERSION=$(nomad version | head -n 1)
  log "Nomad version: $NOMAD_VERSION"
  
  # Check if Nomad server is running
  if nomad server members &> /dev/null; then
    log "Nomad server is running"
  else
    warn "Nomad server might not be running properly"
  fi
  
  # Check if this is a Synology system
  if [[ $(uname -a) == *"synology"* ]]; then
    log "Detected Synology system, will use mount directive in job configurations"
    return 1
  fi
  
  # Check volume capabilities
  log "Checking Nomad volume capabilities..."
  if nomad volume status &> /dev/null; then
    log "Nomad volume command is available"
  else
    warn "Nomad volume command might not be available or configured"
    return 1
  fi
  
  # Check if the host volume type is supported
  log "Creating a test file to check volume syntax..."
  cat > $CONFIG_DIR/test_volume.hcl << EOF
volume "test_volume" {
  type = "host"
  config {
    source = "$DATA_DIR/test"
  }
}
EOF

  # Try to register the test volume
  if nomad volume create $CONFIG_DIR/test_volume.hcl &> /dev/null; then
    log "Host volume type is supported"
    # Clean up test volume
    nomad volume delete test_volume &> /dev/null
    return 0
  else
    warn "Your Nomad installation does not support 'host' volume type"
    return 1
  fi
}

# Generate job templates with mount directive
generate_mount_templates() {
  log "Generating job templates with mount directive..."
  
  # Create directories for templates
  mkdir -p $CONFIG_DIR/volume_templates
  
  # Create a README explaining the mount approach
  cat > $CONFIG_DIR/VOLUME_README.md << EOF
# Volume Configuration for Synology Nomad

## Host Volume Support in Synology

While standard Nomad installations support the \`host\` volume type through \`nomad volume create\`,
Synology's implementation works differently. Instead, use the Docker driver's \`mount\` configuration
in your job specifications.

## Recommended Approach

Use the \`mount\` directive in your job definitions:

\`\`\`hcl
job "example" {
  group "example" {
    task "example" {
      driver = "docker"
      
      config {
        image = "example-image:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/example_data"
          target = "/data"
          readonly = false
        }
      }
    }
  }
}
\`\`\`

This approach is preferred as it uses Nomad's native configuration syntax.

## Alternative Approach

If you encounter issues with the \`mount\` directive, you can also use the Docker-specific \`volumes\` syntax:

\`\`\`hcl
config {
  image = "example-image:latest"
  volumes = [
    "${DATA_DIR}/example_data:/data"
  ]
}
\`\`\`

## Available Volume Directories

The platform has created these directories for your use:

| Directory | Purpose | Path |
|-----------|---------|------|
| High Performance | For services requiring fast I/O | ${DATA_DIR}/high_performance |
| High Capacity | For services requiring large storage | ${DATA_DIR}/high_capacity |
| Standard | For general purpose storage | ${DATA_DIR}/standard |
| Service-specific | Pre-configured for platform services | ${DATA_DIR}/<service_name>_data |
EOF

  # Create Consul template
  cat > $CONFIG_DIR/volume_templates/consul.hcl << EOF
# Consul volume mount example
job "consul" {
  group "consul" {
    task "consul" {
      driver = "docker"
      
      config {
        image = "hashicorp/consul:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/consul_data"
          target = "/consul/data"
          readonly = false
        }
      }
    }
  }
}
EOF

  # Create Vault template
  cat > $CONFIG_DIR/volume_templates/vault.hcl << EOF
# Vault volume mount example
job "vault" {
  group "vault" {
    task "vault" {
      driver = "docker"
      
      config {
        image = "hashicorp/vault:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/vault_data"
          target = "/vault/data"
          readonly = false
        }
      }
    }
  }
}
EOF

  # Create Traefik template
  cat > $CONFIG_DIR/volume_templates/traefik.hcl << EOF
# Traefik volume mount example
job "traefik" {
  group "traefik" {
    task "traefik" {
      driver = "docker"
      
      config {
        image = "traefik:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/certificates"
          target = "/certs"
          readonly = false
        }
        
        mount {
          type = "bind"
          source = "${CONFIG_DIR}/traefik"
          target = "/etc/traefik"
          readonly = true
        }
      }
    }
  }
}
EOF

  # Create Prometheus template
  cat > $CONFIG_DIR/volume_templates/prometheus.hcl << EOF
# Prometheus volume mount example
job "prometheus" {
  group "prometheus" {
    task "prometheus" {
      driver = "docker"
      
      config {
        image = "prom/prometheus:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/prometheus_data"
          target = "/prometheus"
          readonly = false
        }
        
        mount {
          type = "bind"
          source = "${CONFIG_DIR}/prometheus/prometheus.yml"
          target = "/etc/prometheus/prometheus.yml"
          readonly = true
        }
      }
    }
  }
}
EOF

  # Create Grafana template
  cat > $CONFIG_DIR/volume_templates/grafana.hcl << EOF
# Grafana volume mount example
job "grafana" {
  group "grafana" {
    task "grafana" {
      driver = "docker"
      
      config {
        image = "grafana/grafana:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/grafana_data"
          target = "/var/lib/grafana"
          readonly = false
        }
      }
    }
  }
}
EOF

  # Create Docker Registry template
  cat > $CONFIG_DIR/volume_templates/registry.hcl << EOF
# Docker Registry volume mount example
job "registry" {
  group "registry" {
    task "registry" {
      driver = "docker"
      
      config {
        image = "registry:2"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/registry_data"
          target = "/var/lib/registry"
          readonly = false
        }
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/certificates"
          target = "/certs"
          readonly = true
        }
      }
    }
  }
}
EOF

  # Create Loki template
  cat > $CONFIG_DIR/volume_templates/loki.hcl << EOF
# Loki volume mount example
job "loki" {
  group "loki" {
    task "loki" {
      driver = "docker"
      
      config {
        image = "grafana/loki:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/loki_data"
          target = "/loki/data"
          readonly = false
        }
      }
    }
  }
}
EOF

  # Create Keycloak template
  cat > $CONFIG_DIR/volume_templates/keycloak.hcl << EOF
# Keycloak volume mount example
job "keycloak" {
  group "keycloak" {
    task "keycloak" {
      driver = "docker"
      
      config {
        image = "quay.io/keycloak/keycloak:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/keycloak_data"
          target = "/opt/keycloak/data"
          readonly = false
        }
      }
    }
  }
}
EOF

  # Create Homepage template
  cat > $CONFIG_DIR/volume_templates/homepage.hcl << EOF
# Homepage volume mount example
job "homepage" {
  group "homepage" {
    task "homepage" {
      driver = "docker"
      
      config {
        image = "ghcr.io/benphelps/homepage:latest"
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/homepage_data"
          target = "/app/config"
          readonly = false
        }
      }
    }
  }
}
EOF

  success "Job templates with mount directives created in $CONFIG_DIR/volume_templates"
  log "Please refer to $CONFIG_DIR/VOLUME_README.md for guidance on using mount directives"
  
  return 0
}

# Create traditional Nomad volume configurations
create_traditional_volumes() {
  log "Creating traditional Nomad volume configurations..."
  
  # Create the volumes.hcl file
  cat > $CONFIG_DIR/volumes.hcl << EOF
# Storage class volumes
volume "high_performance" {
  type = "host"
  config {
    source = "$DATA_DIR/high_performance"
  }
}

volume "high_capacity" {
  type = "host"
  config {
    source = "$DATA_DIR/high_capacity"
  }
}

volume "standard" {
  type = "host"
  config {
    source = "$DATA_DIR/standard"
  }
}

# Service-specific volumes
volume "consul_data" {
  type = "host"
  config {
    source = "$DATA_DIR/consul_data"
  }
}

volume "vault_data" {
  type = "host"
  config {
    source = "$DATA_DIR/vault_data"
  }
}

volume "registry_data" {
  type = "host"
  config {
    source = "$DATA_DIR/registry_data"
  }
}

volume "prometheus_data" {
  type = "host"
  config {
    source = "$DATA_DIR/prometheus_data"
  }
}

volume "grafana_data" {
  type = "host"
  config {
    source = "$DATA_DIR/grafana_data"
  }
}

volume "loki_data" {
  type = "host"
  config {
    source = "$DATA_DIR/loki_data"
  }
}

volume "postgres_data" {
  type = "host"
  config {
    source = "$DATA_DIR/postgres_data"
  }
}

volume "keycloak_data" {
  type = "host"
  config {
    source = "$DATA_DIR/keycloak_data"
  }
}

volume "homepage_data" {
  type = "host"
  config {
    source = "$DATA_DIR/homepage_data"
  }
}

volume "certificates" {
  type = "host"
  config {
    source = "$DATA_DIR/certificates"
  }
}
EOF
  
  # Register all volumes
  log "Registering all volumes with Nomad..."
  if nomad volume create $CONFIG_DIR/volumes.hcl; then
    success "All volumes created successfully using traditional method"
    return 0
  else
    warn "Failed to create volumes with Nomad"
    return 1
  fi
}

# Main function
main() {
  log "Starting volume configuration..."
  
  # Check if Nomad supports host volumes
  if check_nomad_capabilities; then
    log "Using traditional Nomad volume configuration approach"
    create_traditional_volumes
  else
    log "Using mount directive approach for Synology compatibility"
    generate_mount_templates
  fi
  
  success "Volume configuration completed"
}

# Execute main function
main "$@"