#!/bin/bash
# 02-configure-volumes.sh
# Creates Nomad volume configurations according to documentation

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
  
  # Check volume capabilities
  log "Checking Nomad volume capabilities..."
  if nomad volume status &> /dev/null; then
    log "Nomad volume command is available"
  else
    warn "Nomad volume command might not be available or configured"
  fi
  
  # Check if Synology has CSI plugins enabled
  log "Checking for CSI plugins..."
  if nomad plugin status &> /dev/null; then
    PLUGINS=$(nomad plugin status)
    log "Available plugins: $PLUGINS"
  else
    warn "Cannot get plugin status or no plugins available"
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

  # Output the exact command we're going to run
  log "Will run: nomad volume create $CONFIG_DIR/test_volume.hcl"
  
  # Try to get verbose output from nomad to understand the issue
  VERBOSE_OUTPUT=$(nomad volume create -verbose $CONFIG_DIR/test_volume.hcl 2>&1)
  log "Verbose output from volume creation:"
  echo "$VERBOSE_OUTPUT"
  
  if echo "$VERBOSE_OUTPUT" | grep -q "unknown volume type"; then
    warn "Your Nomad installation does not support 'host' volume type"
    log "Checking if this is a Synology Nomad installation..."
    
    # For Synology, we might need to use a different approach
    if [[ $(uname -a) == *"synology"* ]]; then
      log "Detected Synology system, will use an alternative approach"
      return 1
    fi
  fi
  
  return 0
}

# Generate Nomad job definitions with volume mounts instead
generate_job_configurations() {
  log "Your Nomad installation doesn't support host volumes directly"
  log "Generating job configurations with volume mounts instead..."
  
  # Create directories
  mkdir -p $JOB_DIR
  
  # Create a README explaining the alternative approach
  cat > $CONFIG_DIR/VOLUME_README.md << EOF
# Volume Configuration Alternative

This Nomad installation does not support the 'host' volume type directly.
Instead, you'll need to use volume mounts in your job definitions.

For each service, add the following to your job definition:

\`\`\`hcl
job "service-name" {
  group "service-group" {
    task "service-task" {
      config {
        volumes = [
          "/path/on/host:/path/in/container"
        ]
      }
    }
  }
}
\`\`\`

The directories have been created on the host system and can be used in your job definitions.
EOF

  success "Created VOLUME_README.md with instructions for volume mounts"
  
  # Since we can't use volume plugin, we'll create an alternative method
  log "Directories have been created in $DATA_DIR and can be used in job definitions"
  log "Please refer to $CONFIG_DIR/VOLUME_README.md for guidance"
  
  return 0
}

# Create Nomad volume configurations according to documentation
create_volumes() {
  log "Creating Nomad volume configurations according to documentation..."
  
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
  
  # Print the first few lines of the generated file for debugging
  log "Verifying volumes.hcl file:"
  head -n 10 $CONFIG_DIR/volumes.hcl
  
  # Check if Nomad supports host volumes
  if check_nomad_capabilities; then
    # Try to register all volumes
    log "Registering all volumes with Nomad..."
    if nomad volume create $CONFIG_DIR/volumes.hcl; then
      success "All volumes created successfully"
      return 0
    else
      warn "Failed to create volumes with Nomad"
    fi
  fi
  
  # If we get here, we need to use the alternative approach
  generate_job_configurations
}

# Main function
main() {
  log "Starting volume configuration according to documentation..."
  create_volumes
  success "Volume configuration completed (with alterations as needed)"
}

# Execute main function
main "$@"