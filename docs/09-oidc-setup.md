# OIDC Authentication Setup for Synology DS923+

This document provides detailed information about setting up OIDC (OpenID Connect) authentication for the HomeLab DevOps Platform on Synology DS923+.

## Overview

OIDC (OpenID Connect) is an identity layer built on top of the OAuth 2.0 protocol that allows clients to verify the identity of end-users and to obtain basic profile information. In the HomeLab DevOps Platform, OIDC provides:

- Single sign-on (SSO) across all platform services
- Centralized user management
- Standardized authentication flow
- Enhanced security with token-based authentication
- Integration with existing identity providers

## Architecture

The platform implements OIDC authentication through:

- **Identity Provider**: Keycloak server for authentication
- **OIDC Proxy**: Forward authentication proxy for services that don't natively support OIDC
- **Service Integration**: Direct OIDC integration for services that support it
- **Traefik Middleware**: Authentication middleware for edge protection

## Components

### Keycloak

Keycloak is the primary identity provider:

- **Role**: Central authentication server and user management
- **Features**: User management, role-based access control, client registration
- **Integration**: Works with Traefik for protecting services
- **Storage**: Backed by Vault for secure storage of credentials
- **UI**: Web interface for administration
- **API**: RESTful interface for programmatic access

### Traefik OIDC Middleware

A forward authentication service that integrates with Traefik:

- **Role**: Authenticates requests to services that don't support OIDC natively
- **Flow**: Intercepts requests, verifies authentication, forwards authenticated requests
- **Headers**: Adds user information headers to requests
- **Session**: Manages user sessions and token refreshing

## Memory Optimization for Synology DS923+

With 32GB RAM available on your system, Keycloak is configured with generous resource allocation:

```hcl
# Keycloak resources
resources {
  cpu    = 1000  # 1 core
  memory = 2048  # 2 GB RAM
}

# OIDC Proxy resources
resources {
  cpu    = 200   # 0.2 cores
  memory = 256   # 256 MB RAM
}
```

These allocations provide excellent performance for your authentication stack while still leaving ample resources for other services.

## Configuration

### Keycloak Deployment

Keycloak is deployed as a Nomad job:

```hcl
job "keycloak" {
  datacenters = ["dc1"]
  type = "service"

  group "auth" {
    count = 1

    volume "keycloak_data" {
      type = "host"
      read_only = false
      source = "standard"
    }

    task "keycloak" {
      driver = "docker"

      volume_mount {
        volume = "keycloak_data"
        destination = "/opt/keycloak/data"
        read_only = false
      }

      config {
        image = "quay.io/keycloak/keycloak:latest"
        ports = ["http"]
        
        command = "start-dev"
        
        args = [
          "--http-relative-path=/auth"
        ]
      }

      template {
        data = <<EOF
{{- with secret "kv/data/keycloak/admin" }}
KEYCLOAK_ADMIN={{ .Data.data.username }}
KEYCLOAK_ADMIN_PASSWORD={{ .Data.data.password }}
{{- end }}
EOF
        destination = "secrets/keycloak.env"
        env = true
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      service {
        name = "keycloak"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.keycloak.rule=Host(`auth.homelab.local`)",
          "traefik.http.routers.keycloak.tls=true",
          "homepage.name=Keycloak",
          "homepage.icon=keycloak.png",
          "homepage.group=Security",
          "homepage.description=Identity and access management"
        ]
      }
    }

    network {
      port "http" {
        static = 8080
      }
    }
  }
}
```

### OIDC Proxy Deployment

The OIDC proxy is deployed as a Nomad job:

```hcl
job "oidc-proxy" {
  datacenters = ["dc1"]
  type = "service"

  group "auth" {
    count = 1

    task "proxy" {
      driver = "docker"

      config {
        image = "thomseddon/traefik-forward-auth:latest"
        ports = ["http"]
      }

      template {
        data = <<EOF
{{- with secret "kv/data/oidc/proxy" }}
CLIENT_ID=oidc-proxy
CLIENT_SECRET={{ .Data.data.client_secret }}
{{- end }}
SECRET=something-random-for-cookie-encryption
COOKIE_DOMAIN=homelab.local
AUTH_HOST=auth.homelab.local
PROVIDERS_OIDC_ISSUER_URL=https://auth.homelab.local/auth/realms/homelab
PROVIDERS_OIDC_USER_ID_PATH=preferred_username
EOF
        destination = "secrets/oidc-proxy.env"
        env = true
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "oidc-proxy"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.middlewares.oidc-auth.forwardauth.address=http://{{ env "NOMAD_ADDR_http" }}",
          "traefik.http.middlewares.oidc-auth.forwardauth.authResponseHeaders=X-Forwarded-User,X-Forwarded-Email,X-Forwarded-Groups",
          "traefik.http.middlewares.oidc-auth.forwardauth.trustForwardHeader=true"
        ]
      }
    }

    network {
      port "http" {
        static = 4181
      }
    }
  }
}
```

## Realm Configuration

After Keycloak is deployed, a realm needs to be configured:

1. **Create Realm**: Create a new realm called "homelab"
2. **Configure Realm Settings**:
   - Enable user registration if desired
   - Set access token lifetime
   - Configure email settings

3. **Create Clients**:
   - Create a client for each service that needs to authenticate
   - Set redirect URIs for each client
   - Enable authorization if needed

4. **Create Groups**:
   - Admin group for platform administrators
   - DevOps group for operations users
   - Developer group for application developers

## Service Integration

### Traefik Integration

Traefik uses the OIDC proxy middleware for authentication:

```hcl
# Apply middleware to services that need authentication
tags = [
  "traefik.http.routers.prometheus.middlewares=oidc-auth@consul"
]
```

### Grafana Integration

Grafana supports OIDC natively:

```hcl
template {
  data = <<EOF
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_NAME=OIDC
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=grafana
{{- with secret "kv/data/oidc/grafana" }}
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET={{ .Data.data.client_secret }}
{{- end }}
GF_AUTH_GENERIC_OAUTH_AUTH_URL=https://auth.homelab.local/auth/realms/homelab/protocol/openid-connect/auth
GF_AUTH_GENERIC_OAUTH_TOKEN_URL=https://auth.homelab.local/auth/realms/homelab/protocol/openid-connect/token
GF_AUTH_GENERIC_OAUTH_API_URL=https://auth.homelab.local/auth/realms/homelab/protocol/openid-connect/userinfo
GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=true
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH=contains(groups[*], 'admin') && 'Admin' || contains(groups[*], 'editor') && 'Editor' || 'Viewer'
EOF
  destination = "secrets/grafana-oauth.env"
  env = true
}
```

### Vault Integration

Vault can use OIDC for authentication:

```bash
vault auth enable oidc
vault write auth/oidc/config \
    oidc_discovery_url="https://auth.homelab.local/auth/realms/homelab" \
    oidc_client_id="vault" \
    oidc_client_secret="client-secret" \
    default_role="default"

vault write auth/oidc/role/default \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.homelab.local/ui/vault/auth/oidc/oidc/callback" \
    user_claim="sub" \
    policies="default"
```

## Authentication Flow

The OIDC authentication flow works as follows:

1. User accesses a protected service (e.g., Prometheus)
2. Traefik forwards the request to the OIDC proxy
3. If the user is not authenticated, they are redirected to Keycloak
4. User enters credentials at the Keycloak login page
5. Upon successful authentication, user is redirected back to the OIDC proxy
6. OIDC proxy validates the token and adds user information headers
7. Traefik forwards the authenticated request to the service
8. Service receives the request with user identity information

## User Management

### Creating Users

Users can be created in several ways:

1. **Admin Console**:
   - Log in to Keycloak admin console
   - Navigate to Users section
   - Click "Add User" and fill in details

2. **Self-Registration** (if enabled):
   - User visits Keycloak registration page
   - Fills in required information
   - Verifies email if configured

### Group and Role Management

Access control is managed through:

1. **Groups**: Collections of users with similar access needs
   - Admin group for platform administrators
   - DevOps group for operations users
   - Developer group for application developers

2. **Roles**: Specific permissions assigned to users or groups
   - Admin role for full access
   - Editor role for write access
   - Viewer role for read-only access

## Data Persistence

Keycloak data is persisted on the Synology NAS using a Nomad volume:
- **Volume Name**: keycloak_data
- **Storage Class**: standard
- **Host Path**: `/volume1/nomad/volumes/standard/keycloak_data` (default)
- **Container Path**: `/opt/keycloak/data`

This ensures that user accounts and configuration are maintained across restarts and DSM updates.

## Vault Integration

Keycloak is integrated with Vault for secure storage:

1. **Client Secrets**: Store OIDC client secrets in Vault
2. **Admin Credentials**: Store Keycloak admin credentials in Vault
3. **TLS Certificates**: Store TLS certificates in Vault

Example of retrieving client secrets from Vault:

```hcl
template {
  data = <<EOF
{{- with secret "kv/data/oidc/grafana" }}
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET={{ .Data.data.client_secret }}
{{- end }}
EOF
  destination = "secrets/grafana-oauth.env"
  env = true
}
```

## Handling DSM Updates

When updating your Synology DSM:

1. Keycloak will typically stop during the update
2. User data will remain safe in the persistent volume
3. After the update, Keycloak will restart automatically
4. Sessions will be lost and users will need to re-authenticate

## Security Considerations

For enhanced security:

1. **Enable TLS**: Always use HTTPS for OIDC traffic
2. **Set Appropriate Token Lifetimes**: Limit token validity periods
3. **Use PKCE**: Enable Proof Key for Code Exchange
4. **Implement MFA**: Enable multi-factor authentication for sensitive services
5. **Audit Logging**: Enable audit logs to track authentication events

## Accessing Keycloak

You can access Keycloak through:

1. **Web UI**: `https://auth.homelab.local/auth/admin`
2. **Admin API**: `https://auth.homelab.local/auth/admin/realms/homelab/...`
3. **User Account**: `https://auth.homelab.local/auth/realms/homelab/account`

## Backup and Recovery

### Backing Up Keycloak Data

To backup Keycloak:

```bash
# Option 1: Using Synology Hyper Backup
# Include /volume1/nomad/volumes/standard/keycloak_data in your backup task

# Option 2: Manual backup
# Stop Keycloak
nomad job stop keycloak

# Backup the data directory
tar -czf /volume2/backups/services/keycloak_backup.tar.gz -C /volume1/nomad/volumes/standard keycloak_data

# Restart Keycloak
nomad job run jobs/keycloak.hcl
```

### Restoring Keycloak Data

To restore Keycloak data:

```bash
# Stop Keycloak
nomad job stop keycloak

# Restore the data directory
rm -rf /volume1/nomad/volumes/standard/keycloak_data/*
tar -xzf /volume2/backups/services/keycloak_backup.tar.gz -C /volume1/nomad/volumes/standard

# Restart Keycloak
nomad job run jobs/keycloak.hcl
```

## Troubleshooting

Common issues and their solutions:

1. **Login Failures**:
   - Check Keycloak logs: `nomad alloc logs <keycloak-alloc-id>`
   - Verify user credentials and status
   - Ensure client configuration is correct

2. **Redirect URI Mismatch**:
   - Verify the redirect URI in the client configuration
   - Check for extra slashes or incorrect port numbers
   - Ensure the hostname matches exactly

3. **Token Validation Errors**:
   - Check clock synchronization between services
   - Verify client secret is correct
   - Ensure issuer URL is correct

4. **CORS Issues**:
   - Add the service origin to allowed origins in client settings
   - Check browser console for errors during auth flow
   - Verify Keycloak is configured to allow the correct origins

5. **Integration Problems**:
   - Check service-specific OIDC configuration
   - Verify scope and claim mapping settings
   - Test authentication flow manually

## Next Steps

After setting up OIDC authentication, the next step is to deploy the Homepage dashboard for centralized service access. This is covered in [Homepage Setup](10-homepage-setup.md).