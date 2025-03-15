#!/bin/bash
# 04c-traefik-utils.sh
# Configuration functions for Traefik deployment

# Function to create Traefik configuration
create_traefik_config() {
  log "Creating Traefik job configuration..."
  
  # Ensure job directory exists
  mkdir -p "${JOB_DIR}"
  
  # Default values if not set in config
  TRAEFIK_HTTP_PORT=${TRAEFIK_HTTP_PORT:-80}
  TRAEFIK_HTTPS_PORT=${TRAEFIK_HTTPS_PORT:-443}
  TRAEFIK_ADMIN_PORT=${TRAEFIK_ADMIN_PORT:-8081}
  TRAEFIK_VERSION=${TRAEFIK_VERSION:-"v2.9"}
  TRAEFIK_CPU=${TRAEFIK_CPU:-500}
  TRAEFIK_MEMORY=${TRAEFIK_MEMORY:-512}
  TRAEFIK_HOST=${TRAEFIK_HOST:-"traefik.${DOMAIN:-homelab.local}"}
  CONSUL_HTTP_PORT=${CONSUL_HTTP_PORT:-8500}
  DOMAIN=${DOMAIN:-"homelab.local"}
  
  cat > "${JOB_DIR}/traefik.hcl" << EOF
job "traefik" {
  datacenters = ["dc1"]
  type = "service"

  group "traefik" {
    count = 1

    network {
      port "http" {
        static = ${TRAEFIK_HTTP_PORT}
      }
      port "https" {
        static = ${TRAEFIK_HTTPS_PORT}
      }
      port "admin" {
        static = ${TRAEFIK_ADMIN_PORT}
      }
    }

    task "traefik" {
      driver = "docker"

      config {
        image = "traefik:${TRAEFIK_VERSION}"
        ports = ["http", "https", "admin"]
        
        # Using mount directive instead of volumes for better compatibility
        mount {
          type = "bind"
          source = "local/traefik.toml"
          target = "/etc/traefik/traefik.toml"
          readonly = true
        }
        
        mount {
          type = "bind"
          source = "local/dynamic"
          target = "/etc/traefik/dynamic"
          readonly = false
        }
        
        mount {
          type = "bind"
          source = "${DATA_DIR}/certificates"
          target = "/etc/traefik/certs"
          readonly = true
        }
      }

      template {
        data = <<EOH
[entryPoints]
  [entryPoints.web]
    address = ":${TRAEFIK_HTTP_PORT}"
    [entryPoints.web.http.redirections.entryPoint]
      to = "websecure"
      scheme = "https"
  
  [entryPoints.websecure]
    address = ":${TRAEFIK_HTTPS_PORT}"
  
  [entryPoints.traefik]
    address = ":${TRAEFIK_ADMIN_PORT}"

[api]
  dashboard = true
  insecure = true

[providers.consulCatalog]
  prefix = "traefik"
  exposedByDefault = false
  
  [providers.consulCatalog.endpoint]
    address = "{{ env "NOMAD_IP_http" }}:${CONSUL_HTTP_PORT}"
    scheme = "http"

[providers.file]
  directory = "/etc/traefik/dynamic"
  watch = true

[log]
  level = "DEBUG" # Use DEBUG level to help diagnose issues

[accessLog]

[tls]
  [[tls.certificates]]
    certFile = "/etc/traefik/certs/wildcard.crt"
    keyFile = "/etc/traefik/certs/wildcard.key"
EOH
        destination = "local/traefik.toml"
      }

      # Create dynamic config directory and a placeholder file
      template {
        data = "# This is a placeholder file for the dynamic configuration directory"
        destination = "local/dynamic/placeholder.toml"
      }
      
      # Add basic auth for dashboard if credentials are provided
      template {
        data = <<EOH
{{- if (env "TRAEFIK_DASHBOARD_USER") }}
[http.middlewares.dashboard-auth.basicAuth]
  users = [
    "{{ env "TRAEFIK_DASHBOARD_USER" }}:{{ env "TRAEFIK_DASHBOARD_PASSWORD_HASH" }}"
  ]

[http.routers.dashboard]
  rule = "Host(\`${TRAEFIK_HOST}\`)"
  service = "api@internal"
  entryPoints = ["websecure"]
  middlewares = ["dashboard-auth"]
  tls = true
{{- end }}
EOH
        destination = "local/dynamic/dashboard-auth.toml"
      }

      # Create a sample dynamic configuration file for the dashboard
      template {
        data = <<EOH
[http.routers.dashboard]
  rule = "Host(\`${TRAEFIK_HOST}\`)"
  service = "api@internal"
  entryPoints = ["websecure"]
  tls = true
EOH
        destination = "local/dynamic/dashboard.toml"
      }

      resources {
        cpu    = ${TRAEFIK_CPU}
        memory = ${TRAEFIK_MEMORY}
      }

      service {
        name = "traefik"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.traefik.rule=Host(\`${TRAEFIK_HOST}\`)",
          "traefik.http.routers.traefik.service=api@internal",
          "traefik.http.routers.traefik.tls=true",
          "homepage.name=Traefik",
          "homepage.icon=traefik.png",
          "homepage.group=Infrastructure",
          "homepage.description=Reverse Proxy and Load Balancer"
        ]
        
        check {
          type     = "tcp"   # Use TCP check instead of HTTP
          port     = "admin"
          interval = "30s"  # Longer interval
          timeout  = "5s"   # Longer timeout
          
          # Add a check restart policy to avoid failing the deployment
          check_restart {
            limit = 3
            grace = "120s"
            ignore_warnings = true
          }
        }
      }
    }
  }
}
EOF
  
  # Make sure the job file is readable
  chmod 644 "${JOB_DIR}/traefik.hcl"
  
  success "Traefik job configuration created"
}