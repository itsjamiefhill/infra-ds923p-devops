# Extending the HomeLab DevOps Platform for Synology DS923+

This document provides guidance on how to modify and extend the HomeLab DevOps Platform to meet your specific requirements on Synology DS923+.

## Table of Contents

1. [Adding New Services](#adding-new-services)
2. [Customizing Existing Services](#customizing-existing-services)
3. [Adding Custom Applications](#adding-custom-applications)
4. [Integrating with External Services](#integrating-with-external-services)
5. [Optimizing for Synology DS923+](#optimizing-for-synology-ds923)
6. [Security Enhancements](#security-enhancements)
7. [Advanced Customizations](#advanced-customizations)

## Adding New Services

You can extend the platform by adding new services as Nomad jobs. Here's the general process:

### 1. Create a New Script

Create a new script in the `scripts/` directory following the naming convention:

```bash
touch scripts/13-deploy-new-service.sh
chmod +x scripts/13-deploy-new-service.sh
```

### 2. Define the Job

Create a job definition in the `jobs/` directory:

```bash
touch jobs/new-service.hcl
```

### 3. Script Structure

Follow this template for your deployment script:

```bash
#!/bin/bash
# 13-deploy-new-service.sh
# Deploys a new service

set -e

# Script directory and import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "${PARENT_DIR}/config/default.conf"

# If custom config exists, load it
if [ -f "${PARENT_DIR}/config/custom.conf" ]; then
    source "${PARENT_DIR}/config/custom.conf"
fi

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

# Create and deploy your new service
deploy_new_service() {
  log "Creating new service job configuration..."
  
  # Add configuration variables to default.conf or custom.conf
  
  # Create the job definition
  cat > $JOB_DIR/new-service.hcl << EOF
job "new-service" {
  datacenters = ["dc1"]
  type = "service"

  group "new-service" {
    count = 1

    volume "app_data" {
      type = "host"
      read_only = false
      source = "standard"
    }

    task "app" {
      driver = "docker"

      volume_mount {
        volume = "app_data"
        destination = "/data"
        read_only = false
      }

      config {
        image = "your-image:tag"
        ports = ["http"]
      }

      # If you need secrets from Vault
      template {
        data = <<EOH
{{- with secret "kv/data/new-service/config" }}
ENV_VAR_1={{ .Data.data.var1 }}
ENV_VAR_2={{ .Data.data.var2 }}
{{- end }}
EOH
        destination = "secrets/service-env"
        env = true
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "new-service"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.newservice.rule=Host(\`new-service.homelab.local\`)",
          "traefik.http.routers.newservice.tls=true",
          "traefik.http.routers.newservice.middlewares=oidc-auth@consul",
          "homepage.name=New Service",
          "homepage.icon=service.png",
          "homepage.group=Custom",
          "homepage.description=My custom service"
        ]
      }
    }

    network {
      port "http" {
        static = 8095
      }
    }
  }
}
EOF
  
  log "Deploying new service job to Nomad..."
  nomad job run $JOB_DIR/new-service.hcl || error "Failed to deploy new service job"
  
  success "New service deployment completed"
}

# Store secrets in Vault if needed
setup_vault_secrets() {
  log "Setting up Vault secrets for new service..."
  
  # Get Vault allocation ID
  VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
  
  # Check if Vault is unsealed
  VAULT_SEALED=$(nomad alloc exec -task vault ${VAULT_ALLOC} vault status -format=json 2>/dev/null | jq -r '.sealed')
  
  if [ "${VAULT_SEALED}" == "false" ]; then
    log "Storing secrets in Vault..."
    nomad alloc exec -task vault ${VAULT_ALLOC} vault kv put kv/new-service/config var1="value1" var2="value2"
    success "Secrets stored in Vault"
  else
    warn "Vault is sealed. Skipping secret storage."
  fi
}

# Configure OIDC if needed
setup_oidc_integration() {
  log "Setting up OIDC integration for new service..."
  
  # Generate a client secret
  CLIENT_SECRET=$(openssl rand -hex 16)
  
  # Store the client secret in Vault
  VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
  VAULT_SEALED=$(nomad alloc exec -task vault ${VAULT_ALLOC} vault status -format=json 2>/dev/null | jq -r '.sealed')
  
  if [ "${VAULT_SEALED}" == "false" ]; then
    log "Storing client secret in Vault..."
    nomad alloc exec -task vault ${VAULT_ALLOC} vault kv put kv/oidc/new-service client_id="new-service" client_secret="${CLIENT_SECRET}"
    success "Client secret stored in Vault"
  else
    warn "Vault is sealed. Skipping client secret storage."
  fi
  
  # Get Keycloak allocation ID
  KEYCLOAK_ALLOC=$(nomad job allocs -job keycloak -latest | tail -n +2 | awk '{print $1}')
  
  # Add the client to Keycloak (using curl or other methods)
  log "Creating OIDC client in Keycloak..."
  
  # Get admin token (you'll need to get admin credentials from Vault)
  ADMIN_TOKEN=$(curl -s -d "client_id=admin-cli" -d "username=${KEYCLOAK_ADMIN}" -d "password=${KEYCLOAK_PASSWORD}" -d "grant_type=password" https://auth.homelab.local/auth/realms/master/protocol/openid-connect/token | jq -r '.access_token')
  
  # Create client
  curl -s -X POST -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" -d '{
    "clientId": "new-service",
    "secret": "'"${CLIENT_SECRET}"'",
    "redirectUris": ["https://new-service.homelab.local/*"],
    "webOrigins": ["https://new-service.homelab.local"],
    "enabled": true,
    "protocol": "openid-connect",
    "publicClient": false
  }' https://auth.homelab.local/auth/admin/realms/homelab/clients
  
  success "OIDC integration configured"
}

# Update host entries
update_host_entries() {
  log "Updating host entries..."
  
  if grep -q "new-service.homelab.local" /etc/hosts; then
    log "Host entry already exists"
  else
    log "Adding host entry for new-service.homelab.local"
    sudo bash -c "echo \"${SYNOLOGY_IP} new-service.homelab.local\" >> /etc/hosts"
  fi
  
  success "Host entries updated"
}

# Main function
main() {
  log "Starting new service deployment..."
  setup_vault_secrets
  setup_oidc_integration
  deploy_new_service
  update_host_entries
  success "New service setup completed"
}

# Execute main function
main "$@"
```

### 4. Update Main Installation Script

Add your script to the main installation flow in `install.sh`:

```bash
# Run module scripts in order
...
run_module "12-create-summary.sh"
run_module "13-deploy-new-service.sh"  # Add your new module
```

### 5. Update Homepage Configuration

Make sure your new service appears on the Homepage dashboard by editing the template in `scripts/10-deploy-homepage.sh`:

```yaml
# In the services.yml template block
- Custom:
  - New Service:
      icon: service.png
      href: https://new-service.homelab.local
      description: My custom service
      widget:
        type: iframe
        url: https://new-service.homelab.local/status
```

## Customizing Existing Services

You can customize existing services by modifying their configuration and job definitions.

### 1. Add Configuration Variables

Add new configuration variables in `config/custom.conf`:

```bash
# Custom settings for existing service
GRAFANA_PLUGINS="grafana-piechart-panel,grafana-worldmap-panel"
PROMETHEUS_RETENTION_TIME="15d"
LOKI_RETENTION_PERIOD="168h"
```

### 2. Modify the Deployment Script

Update the relevant deployment script to use your new variables:

```bash
# In scripts/07-deploy-monitoring.sh
template {
  data = <<EOF
GF_INSTALL_PLUGINS = "${GRAFANA_PLUGINS}"  # Add your custom setting
EOF
  destination = "local/grafana.env"
  env = true
}
```

### 3. Redeploy the Service

Run the specific deployment script to apply changes:

```bash
./scripts/07-deploy-monitoring.sh
```

### 4. Customizing Traefik

Traefik can be customized for advanced routing and middleware:

```bash
# In config/custom.conf
TRAEFIK_ADDITIONAL_CONFIG="
[http.middlewares]
  [http.middlewares.redirect-non-www.redirectregex]
    regex = '^https://www.(.*)'
    replacement = 'https://\${1}'
"
```

### 5. Vault Configuration

Customize Vault's configuration for advanced features:

```bash
# In config/custom.conf
VAULT_ADDITIONAL_CONFIG="
telemetry {
  prometheus_retention_time = \"30s\"
  disable_hostname = true
}

listener \"tcp\" {
  address = \"0.0.0.0:8200\"
  tls_disable = 0
  tls_cert_file = \"/vault/certs/homelab.crt\"
  tls_key_file = \"/vault/certs/homelab.key\"
}
"
```

## Adding Custom Applications

Use this platform as a base for deploying your own applications:

### 1. Create a New Application Script

```bash
cp scripts/13-deploy-new-service.sh scripts/14-deploy-my-app.sh
```

### 2. Customize the Application Deployment

Modify the script to deploy your custom application:

```bash
cat > $JOB_DIR/my-app.hcl << EOF
job "my-app" {
  datacenters = ["dc1"]
  type = "service"

  group "app" {
    count = 1

    volume "app_data" {
      type = "host"
      read_only = false
      source = "standard"
    }

    task "app" {
      driver = "docker"

      volume_mount {
        volume = "app_data"
        destination = "/app/data"
        read_only = false
      }

      config {
        image = "registry.homelab.local:5000/my-app:latest"
        ports = ["http"]
      }
      
      # Add Vault integration for secrets
      template {
        data = <<EOH
{{- with secret "kv/data/my-app/config" }}
APP_SECRET={{ .Data.data.secret }}
DB_PASSWORD={{ .Data.data.db_password }}
{{- end }}
EOH
        destination = "secrets/app-env"
        env = true
      }

      # Add OIDC integration
      template {
        data = <<EOH
OIDC_ISSUER=https://auth.homelab.local/auth/realms/homelab
OIDC_CLIENT_ID=my-app
{{- with secret "kv/data/oidc/my-app" }}
OIDC_CLIENT_SECRET={{ .Data.data.client_secret }}
{{- end }}
OIDC_REDIRECT_URI=https://my-app.homelab.local/callback
EOH
        destination = "secrets/oidc-env"
        env = true
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "my-app"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.myapp.rule=Host(`my-app.homelab.local`)",
          "traefik.http.routers.myapp.tls=true",
          "homepage.name=My Application",
          "homepage.icon=app.png",
          "homepage.group=Applications",
          "homepage.description=My custom application"
        ]
      }
    }

    network {
      port "http" {
        static = 8100
      }
    }
  }
}
EOF
```

### 3. Integrate with Existing Services

Make sure your application leverages the platform's features:

1. **Service Discovery**: Register with Consul for discovery
2. **Authentication**: Use OIDC for authentication
3. **Secrets Management**: Store sensitive configuration in Vault
4. **Monitoring**: Expose Prometheus metrics for monitoring
5. **Logging**: Send logs to Loki for centralized logging
6. **Container Registry**: Push images to the internal registry

### 4. Example Application Integration

Here's an example of how to integrate a Node.js application:

```javascript
// app.js
const express = require('express');
const { Issuer, Strategy } = require('openid-client');
const passport = require('passport');
const session = require('express-session');
const promClient = require('prom-client');
const winston = require('winston');

const app = express();

// Logging setup
const logger = winston.createLogger({
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      )
    })
  ]
});

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });
const httpRequestDurationMicroseconds = new promClient.Histogram({
  name: 'http_request_duration_ms',
  help: 'Duration of HTTP requests in ms',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.1, 5, 15, 50, 100, 500]
});
register.registerMetric(httpRequestDurationMicroseconds);

// OIDC setup
async function setupOIDC() {
  const issuer = await Issuer.discover(process.env.OIDC_ISSUER);
  const client = new issuer.Client({
    client_id: process.env.OIDC_CLIENT_ID,
    client_secret: process.env.OIDC_CLIENT_SECRET,
    redirect_uris: [process.env.OIDC_REDIRECT_URI],
    response_types: ['code']
  });

  passport.use('oidc', new Strategy({ client }, (tokenSet, userinfo, done) => {
    return done(null, userinfo);
  }));

  passport.serializeUser((user, done) => {
    done(null, user);
  });

  passport.deserializeUser((user, done) => {
    done(null, user);
  });
}

setupOIDC().catch(err => {
  logger.error('OIDC setup failed', { error: err.message });
});

// Middleware
app.use(session({
  secret: process.env.APP_SECRET,
  resave: false,
  saveUninitialized: true
}));
app.use(passport.initialize());
app.use(passport.session());

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(register.metrics());
});

// Authentication
app.get('/login', passport.authenticate('oidc'));
app.get('/callback', passport.authenticate('oidc', {
  successRedirect: '/',
  failureRedirect: '/login'
}));

// Protected routes
app.get('/', (req, res) => {
  if (!req.isAuthenticated()) {
    return res.redirect('/login');
  }
  res.send(`Hello ${req.user.name}!`);
});

// Start server
const port = process.env.PORT || 3000;
app.listen(port, () => {
  logger.info(`Server listening on port ${port}`);
});
```

## Integrating with External Services

You can extend the platform to work with external services:

### 1. Add External Service Configuration

Add external service details to `config/custom.conf`:

```bash
# External service configuration
EXTERNAL_SERVICE_URL="https://external-api.example.com"
EXTERNAL_SERVICE_KEY="your-api-key"
```

### 2. Store Sensitive Credentials in Vault

Use Vault to securely store external service credentials:

```bash
# Add this to your deployment script
VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
nomad alloc exec -task vault ${VAULT_ALLOC} vault kv put kv/external-service/api key="your-api-key" secret="your-api-secret"
```

### 3. Create an Integration Job

Create a job that connects to the external service:

```hcl
job "external-integration" {
  datacenters = ["dc1"]
  type = "service"

  group "integration" {
    count = 1

    task "connector" {
      driver = "docker"

      config {
        image = "registry.homelab.local:5000/external-connector:latest"
      }
      
      template {
        data = <<EOH
{{- with secret "kv/data/external-service/api" }}
API_URL=${EXTERNAL_SERVICE_URL}
API_KEY={{ .Data.data.key }}
API_SECRET={{ .Data.data.secret }}
{{- end }}
EOH
        destination = "secrets/api-env"
        env = true
      }

      service {
        name = "external-connector"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.external.rule=Host(`external.homelab.local`)",
          "homepage.name=External Integration",
          "homepage.icon=external.png",
          "homepage.group=Integrations",
          "homepage.description=External service integration"
        ]
      }
    }

    network {
      port "http" {
        static = 8200
      }
    }
  }
}
```

## Optimizing for Synology DS923+

### 1. Memory Optimization

Adjust memory allocations based on service importance:

```bash
# In config/custom.conf
# Optimize for 32GB RAM on DS923+
PROMETHEUS_MEMORY=4096  # 4GB for metrics storage
LOKI_MEMORY=3072        # 3GB for log storage
KEYCLOAK_MEMORY=2048    # 2GB for authentication
VAULT_MEMORY=1536       # 1.5GB for secrets management
GRAFANA_MEMORY=1024     # 1GB for dashboards
CONSUL_MEMORY=1024      # 1GB for service discovery
REGISTRY_MEMORY=1024    # 1GB for Docker images
TRAEFIK_MEMORY=512      # 512MB for proxy
HOMEPAGE_MEMORY=512     # 512MB for dashboard
OIDC_PROXY_MEMORY=256   # 256MB for auth proxy
PROMTAIL_MEMORY=256     # 256MB for log shipping
```

### 2. Storage Class Allocation

Optimize storage class usage based on access patterns:

```hcl
# Update volume definitions for each service
# In Prometheus job
volume "prometheus_storage" {
  type = "host"
  read_only = false
  source = "high_performance"  # For fast query performance
}

# In Loki job
volume "loki_storage" {
  type = "host"
  read_only = false
  source = "high_capacity"  # For large log volumes
}
```

### 3. Docker Image Cleanup

Add a scheduled job to clean up unused Docker images:

```hcl
job "cleanup" {
  datacenters = ["dc1"]
  type = "batch"
  
  periodic {
    cron = "0 2 * * 0"  # Weekly at 2 AM on Sunday
    prohibit_overlap = true
  }

  group "maintenance" {
    task "docker-cleanup" {
      driver = "exec"
      
      config {
        command = "/bin/bash"
        args    = ["-c", "docker system prune -af"]
      }
      
      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
```

### 4. Backup Integration

Create a job that integrates with Synology's Hyper Backup:

```hcl
job "backup-preparation" {
  datacenters = ["dc1"]
  type = "batch"
  
  periodic {
    cron = "0 1 * * *"  # Daily at 1 AM
    prohibit_overlap = true
  }

  group "backup" {
    task "pre-backup" {
      driver = "exec"
      
      config {
        command = "/bin/bash"
        args    = ["/volume1/nomad/scripts/pre-backup.sh"]
      }
      
      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
```

## Security Enhancements

### 1. Hardening Vault

Enhance Vault security configurations:

```bash
# In config/custom.conf
VAULT_ADDITIONAL_CONFIG="
audit {
  type = \"file\"
  path = \"/vault/logs/audit.log\"
}

ui {
  headers {
    \"content-security-policy\" = \"default-src 'self' 'unsafe-inline' 'unsafe-eval';\"
    \"x-content-type-options\" = \"nosniff\"
    \"x-frame-options\" = \"DENY\"
  }
}
"
```

### 2. Enhanced OIDC Security

Improve OIDC configuration with additional security measures:

```bash
# In config/custom.conf
KEYCLOAK_ADDITIONAL_CONFIG="
  eventsEnabled: true
  eventsExpiration: 43200
  enabledEventTypes: [ LOGIN, LOGIN_ERROR, LOGOUT, LOGOUT_ERROR ]
  bruteForceProtected: true
  permanentLockout: false
  maxFailureWaitSeconds: 900
  minimumQuickLoginWaitSeconds: 60
  waitIncrementSeconds: 60
  quickLoginCheckMilliSeconds: 1000
  maxDeltaTimeSeconds: 43200
  failureFactor: 5
"
```

### 3. Secure Database Integration

When adding a database, implement enhanced security:

```hcl
job "database" {
  // ...

  group "postgres" {
    // ...

    task "postgres" {
      // ...
      
      env {
        POSTGRES_PASSWORD_FILE = "/secrets/db_password"
        POSTGRES_USER_FILE = "/secrets/db_user"
        POSTGRES_DB_FILE = "/secrets/db_name"
      }
      
      template {
        data = <<EOH
{{- with secret "database/creds/app-user" }}
{{ .Data.username }}
{{- end }}
EOH
        destination = "secrets/db_user"
      }
      
      template {
        data = <<EOH
{{- with secret "database/creds/app-user" }}
{{ .Data.password }}
{{- end }}
EOH
        destination = "secrets/db_password"
        perms = "0400"
      }
    }
  }
}
```

### 4. Certificate Rotation

Set up automatic certificate rotation:

```bash
#!/bin/bash
# certificate-rotation.sh
# Rotate self-signed certificates annually

# Generate new certificates
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /volume1/nomad/config/certs/homelab.key \
  -out /volume1/nomad/config/certs/homelab.crt \
  -subj "/CN=*.homelab.local" \
  -addext "subjectAltName=DNS:*.homelab.local,DNS:homelab.local"

# Copy to volumes directory for mounting
cp /volume1/nomad/config/certs/homelab.* /volume1/nomad/volumes/certificates/

# Restart Traefik to pick up new certificates
nomad job restart traefik
```

## Advanced Customizations

### 1. Custom Docker Images

Build custom Docker images for specialized requirements:

```bash
# Build a custom image
docker build -t registry.homelab.local:5000/custom-app:latest .

# Push to local registry
docker push registry.homelab.local:5000/custom-app:latest

# Use in job definition
image = "registry.homelab.local:5000/custom-app:latest"
```

### 2. Service Mesh with Consul Connect

Enable service mesh capabilities for secure service-to-service communication:

```hcl
job "service-with-mesh" {
  datacenters = ["dc1"]
  type = "service"

  group "app" {
    network {
      mode = "bridge"
      
      port "http" {
        to = 8080
      }
    }
    
    service {
      name = "meshed-service"
      port = "http"
      
      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "another-service"
              local_bind_port = 9090
            }
          }
        }
      }
    }
    
    task "app" {
      driver = "docker"
      
      config {
        image = "registry.homelab.local:5000/meshed-app:latest"
      }
      
      # Rest of task definition...
    }
  }
}
```

### 3. Custom Grafana Dashboards

Create custom Grafana dashboards for your specific needs:

```bash
# In your deployment script
cat > /volume1/nomad/volumes/standard/grafana_data/dashboards/custom.json << EOF
{
  "dashboard": {
    "title": "Synology DS923+ System Dashboard",
    "panels": [
      // Dashboard definition...
    ]
  }
}
EOF
```

### 4. Advanced Load Balancing

Implement advanced load balancing strategies with Traefik:

```hcl
service {
  name = "backend-service"
  port = "http"
  
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.backend.rule=Host(`api.homelab.local`)",
    "traefik.http.services.backend.loadbalancer.sticky=true",
    "traefik.http.services.backend.loadbalancer.sticky.cookie.name=backend_sticky",
    "traefik.http.services.backend.loadbalancer.sticky.cookie.secure=true",
    "traefik.http.services.backend.loadbalancer.sticky.cookie.httpOnly=true"
  ]
}
```

### 5. Synology DSM Integration

Integrate with Synology-specific features:

```bash
# Add to custom.conf
DSM_INTEGRATION_ENABLED=true

# In your script
if [ "${DSM_INTEGRATION_ENABLED}" = "true" ]; then
  # Create Synology task in Task Scheduler
  syno_task_create() {
    # Implementation to create a scheduled task in Synology DSM
    # This would typically use Synology API or direct command
  }
  
  # Set up notification integration
  syno_notification_setup() {
    # Implementation to set up notifications in DSM
  }
  
  syno_task_create
  syno_notification_setup
fi
```

## Best Practices

1. **Test Changes in Development**: Always test changes in a development environment before applying to production.

2. **Version Control**: Keep all customizations in version control.

3. **Documentation**: Document all custom changes and additions.

4. **Backup Before Changes**: Always backup before making significant changes.

5. **Incremental Changes**: Make changes incrementally and test each step.

6. **Monitor Impact**: Monitor the impact of changes on system resources.

7. **Security Review**: Review security implications of any changes.

8. **Maintain Compatibility**: Ensure changes remain compatible with future platform updates.

9. **Synology-Specific Considerations**: Be aware of DSM update impacts and Synology-specific limitations.

10. **Resource Management**: Keep an eye on resource usage, particularly with the Synology DS923+ processor and memory.