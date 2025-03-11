# Network Configuration for HomeLab DevOps Platform

This document provides detailed information about the network configuration for the HomeLab DevOps Platform on Synology DS923+.

## Table of Contents

1. [Overview](#overview)
2. [Network Architecture](#network-architecture)
3. [Synology Network Configuration](#synology-network-configuration)
4. [Firewall Configuration](#firewall-configuration)
5. [DNS Configuration](#dns-configuration)
6. [Service Discovery](#service-discovery)
7. [TLS and Certificate Management](#tls-and-certificate-management)
8. [Access Control](#access-control)
9. [Monitoring Network Traffic](#monitoring-network-traffic)
10. [Troubleshooting](#troubleshooting)

## Overview

The HomeLab DevOps Platform uses a comprehensive network configuration to ensure services are secure, discoverable, and properly isolated. This document covers all aspects of the network setup, from initial Synology configuration to service-specific settings.

## Network Architecture

### Local Network Overview

The platform operates within a local network:
- **Network Subnet**: 10.0.4.0/24
- **Synology IP Address**: Static IP (e.g., 10.0.4.10)
- **No External Exposure**: All services remain internal
- **Reverse Proxy**: Traefik acts as the central entry point
- **Service Discovery**: Consul provides DNS-based service discovery

### Network Diagram

```
                        ┌────────────────────────────────────────────────┐
                        │                                                │
                        │               Local Network                    │
                        │               (10.0.4.0/24)                    │
                        │                                                │
                        └───────────────────┬────────────────────────────┘
                                            │
                                            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Synology DS923+                                 │
│                                                                             │
│  ┌───────────────┐    ┌─────────────┐    ┌───────────────────────────────┐  │
│  │               │    │             │    │                               │  │
│  │  Traefik      │◄───┤  Consul     │◄───┤  Services                     │  │
│  │  (Ports 80/443)│    │  (DNS/API)  │    │  (Vault, Prometheus, etc.)    │  │
│  │               │    │             │    │                               │  │
│  └───────┬───────┘    └─────────────┘    └───────────────────────────────┘  │
│          │                                                                  │
└──────────┼──────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                  Client Devices (Laptops, Phones, etc.)                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Port Allocation

| Service | Port(s) | Protocol | Purpose |
|---------|---------|----------|---------|
| Traefik | 80, 443 | TCP | HTTP/HTTPS entrypoints |
| Traefik Dashboard | 8081 | TCP | Admin interface |
| Consul | 8500 | TCP | HTTP API |
| Consul | 8600 | TCP/UDP | DNS interface |
| Consul | 8300-8302 | TCP/UDP | Server and gossip |
| Nomad | 4646-4648 | TCP | HTTP API and RPC |
| Vault | 8200 | TCP | API and UI |
| Prometheus | 9090 | TCP | HTTP API and UI |
| Grafana | 3000 | TCP | HTTP API and UI |
| Loki | 3100 | TCP | HTTP API |
| Registry | 5000 | TCP | Docker Registry API |
| Keycloak | 8080 | TCP | Authentication service |
| OIDC Proxy | 4181 | TCP | Forward authentication |
| Homepage | 3000 | TCP | Dashboard |

## Synology Network Configuration

### Static IP Configuration

Configure your Synology DS923+ with a static IP:

1. In DSM, go to **Control Panel** > **Network** > **Network Interface**
2. Select your primary network interface and click **Edit**
3. Select **Use manual configuration**
4. Configure the following:
   - IP Address: 10.0.4.10 (or your preferred static IP)
   - Subnet Mask: 255.255.255.0
   - Gateway: 10.0.4.1 (your router IP)
   - DNS Server: 10.0.4.1 (your router IP or preferred DNS)

### Network Interface Settings

For optimal performance:

1. **Link Aggregation** (if your network supports it):
   - In DSM, go to **Control Panel** > **Network** > **Network Interface**
   - Click **Create** > **Create Bond**
   - Select IEEE 802.3ad Dynamic Link Aggregation
   - Select the network interfaces to bond
   - Complete the setup wizard

2. **Jumbo Frames** (if your network supports it):
   - In DSM, go to **Control Panel** > **Network** > **Network Interface**
   - Select your interface and click **Edit**
   - Set MTU to 9000 (or the maximum supported by your network)

3. **Traffic Control** (optional):
   - In DSM, go to **Control Panel** > **Network** > **Traffic Control**
   - Enable and configure guaranteed bandwidth for services

## Firewall Configuration

### Synology Firewall

Configure the DSM firewall to allow required services:

1. In DSM, go to **Control Panel** > **Security** > **Firewall**
2. Create a profile for your network interface
3. Set default action to **Deny** for safer defaults
4. Add the following rules:

```
# Allow SSH from management IPs only
Source: [Your trusted IP addresses]
Port: 22
Protocol: TCP
Action: Allow

# Allow HTTP/HTTPS from local network
Source: 10.0.4.0/24
Ports: 80, 443
Protocol: TCP
Action: Allow

# Allow platform services from local network
Source: 10.0.4.0/24
Ports: 4646-4648, 8300-8302, 8500, 8600, 8081
Protocol: TCP
Action: Allow

# Allow UDP ports for Consul
Source: 10.0.4.0/24
Ports: 8301-8302, 8600
Protocol: UDP
Action: Allow
```

### Service-Specific Firewall Considerations

For more granular control, you can limit certain services to specific clients:

```
# Limit Vault management to admin workstations
Source: 10.0.4.5, 10.0.4.6
Port: 8200
Protocol: TCP
Action: Allow

# Limit Prometheus direct access to monitoring workstations
Source: 10.0.4.7
Port: 9090
Protocol: TCP
Action: Allow
```

## DNS Configuration

### Hosts File Configuration

For client devices, add entries to the hosts file:

```
# /etc/hosts (Linux/Mac) or C:\Windows\System32\drivers\etc\hosts (Windows)
10.0.4.10  consul.homelab.local
10.0.4.10  vault.homelab.local
10.0.4.10  traefik.homelab.local
10.0.4.10  grafana.homelab.local
10.0.4.10  prometheus.homelab.local
10.0.4.10  loki.homelab.local
10.0.4.10  registry.homelab.local
10.0.4.10  auth.homelab.local
10.0.4.10  home.homelab.local
```

### Consul DNS Integration

To use Consul for service discovery DNS:

1. Configure the Synology DNS server to forward Consul requests:
   ```bash
   sudo mkdir -p /etc/dnsmasq.conf.d
   echo "server=/consul/127.0.0.1#8600" | sudo tee /etc/dnsmasq.conf.d/10-consul
   sudo systemctl restart dnsmasq
   ```

2. Test DNS resolution:
   ```bash
   dig @127.0.0.1 consul.service.consul
   ```

3. For client devices, add your Synology as a DNS server:
   - DNS Server: 10.0.4.10 (your Synology IP)
   - This allows resolution of both `.homelab.local` and `.service.consul` domains

## Service Discovery

### Consul Service Registration

Services register themselves with Consul for discovery:

```hcl
service {
  name = "grafana"
  port = "http"
  
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.grafana.rule=Host(`grafana.homelab.local`)",
    "traefik.http.routers.grafana.tls=true",
    "homepage.name=Grafana",
    "homepage.icon=grafana.png",
    "homepage.group=Monitoring",
    "homepage.description=Metrics visualization and dashboards"
  ]
  
  check {
    type     = "http"
    path     = "/api/health"
    interval = "10s"
    timeout  = "2s"
  }
}
```

### Consul DNS Usage

Access services using DNS:

```bash
# Using full service name
curl http://grafana.service.consul:3000

# Using SRV record
dig @127.0.0.1 -p 8600 grafana.service.consul SRV

# Automatic port discovery
curl http://grafana.service.consul
```

## TLS and Certificate Management

### Self-Signed Certificates

TLS is implemented using self-signed certificates:

1. Certificate files are stored at:
   - Public certificate: `/volume1/docker/nomad/config/certs/homelab.crt`
   - Private key: `/volume1/docker/nomad/config/certs/homelab.key`

2. These certificates are mounted into Traefik:
   ```hcl
   volume "certificates" {
     type = "host"
     read_only = true
     source = "certificates"
   }

   volume_mount {
     volume = "certificates"
     destination = "/etc/traefik/certs"
     read_only = true
   }
   ```

3. Traefik is configured to use these certificates:
   ```toml
   [tls]
     [[tls.certificates]]
       certFile = "/etc/traefik/certs/homelab.crt"
       keyFile = "/etc/traefik/certs/homelab.key"
   ```

### Client Certificate Trust

For client devices to trust the certificates:

1. Import the certificate to the trust store:
   - Windows: Import to "Trusted Root Certification Authorities"
   - macOS: Import to Keychain, set to "Always Trust"
   - Linux: Add to `/usr/local/share/ca-certificates/` and run `update-ca-certificates`
   - iOS/Android: Install certificate profile

2. For Docker clients:
   ```bash
   # Create directory for certificates
   sudo mkdir -p /etc/docker/certs.d/registry.homelab.local:5000

   # Copy your self-signed certificate
   sudo cp homelab.crt /etc/docker/certs.d/registry.homelab.local:5000/ca.crt

   # Restart Docker
   sudo systemctl restart docker
   ```

## Access Control

### Network-Level Access Control

Access to services is controlled at multiple levels:

1. **Firewall Rules**: Restrict access by IP and port
2. **Traefik Middleware**: OIDC authentication for services
3. **Service-Specific Authentication**: Direct OIDC integration

### Traefik OIDC Integration

Traefik uses OIDC for authentication:

```hcl
# OIDC middleware configuration
tags = [
  "traefik.http.middlewares.oidc-auth.forwardauth.address=http://oidc-proxy.service.consul:4181",
  "traefik.http.middlewares.oidc-auth.forwardauth.authResponseHeaders=X-Forwarded-User,X-Forwarded-Email,X-Forwarded-Groups",
  "traefik.http.middlewares.oidc-auth.forwardauth.trustForwardHeader=true"
]

# Apply middleware to protected services
tags = [
  "traefik.http.routers.prometheus.middlewares=oidc-auth@consul"
]
```

## Monitoring Network Traffic

### Network Traffic Monitoring

Monitor network traffic with Prometheus and Grafana:

1. **Node Exporter** collects basic network metrics:
   - Bytes received/transmitted
   - Packets received/transmitted
   - Network errors and drops

2. **Example Prometheus Queries**:
   ```
   # Network throughput (bytes per second)
   rate(node_network_receive_bytes_total{device="eth0"}[5m])
   rate(node_network_transmit_bytes_total{device="eth0"}[5m])
   
   # Network errors
   rate(node_network_receive_errs_total{device="eth0"}[5m])
   ```

3. **Service-specific Network Metrics**:
   ```
   # Traefik request rate
   sum(rate(traefik_router_requests_total[5m])) by (router)
   
   # HTTP status codes
   sum(rate(traefik_router_requests_total[5m])) by (code)
   ```

### Traefik Access Logs

Configure Traefik to log access requests:

```toml
[accessLog]
  filePath = "/var/log/traefik/access.log"
  format = "json"
  bufferingSize = 100
```

These logs are collected by Promtail and stored in Loki for analysis:

```yaml
# In Promtail configuration
scrape_configs:
  - job_name: traefik
    static_configs:
    - targets:
        - localhost
      labels:
        job: traefik
        host: ${HOSTNAME}
        __path__: /var/log/traefik/access.log
```

## Troubleshooting

### Common Network Issues

1. **DNS Resolution Issues**:
   ```bash
   # Test Consul DNS
   dig @127.0.0.1 -p 8600 consul.service.consul
   
   # Test local resolution
   ping grafana.homelab.local
   
   # Check dnsmasq configuration
   cat /etc/dnsmasq.conf.d/10-consul
   ```

2. **Connection Refused Errors**:
   ```bash
   # Check if the service is running
   nomad job status <job-name>
   
   # Verify the port is open
   ss -tulpn | grep <port>
   
   # Check firewall rules
   sudo iptables -L
   ```

3. **Certificate Errors**:
   ```bash
   # Verify certificate validity
   openssl x509 -in /volume1/docker/nomad/config/certs/homelab.crt -text -noout
   
   # Test HTTPS connection
   curl -v -k https://grafana.homelab.local
   ```

4. **Service Discovery Problems**:
   ```bash
   # Check if service is registered
   curl http://localhost:8500/v1/catalog/service/<service-name>
   
   # Check health status
   curl http://localhost:8500/v1/health/service/<service-name>
   ```

### Network Diagnostic Tools

1. **Basic Network Tools**:
   ```bash
   # Check connectivity
   ping <host>
   
   # Trace route
   traceroute <host>
   
   # Check open ports
   nmap -p 1-65535 localhost
   ```

2. **Consul DNS Debugging**:
   ```bash
   # Check Consul DNS service
   dig @127.0.0.1 -p 8600 consul.service.consul
   
   # List all services
   dig @127.0.0.1 -p 8600 +short service.consul SRV
   
   # Check specific service
   dig @127.0.0.1 -p 8600 +short grafana.service.consul SRV
   ```

3. **Traefik Debugging**:
   ```bash
   # Check Traefik routers
   curl -s http://localhost:8081/api/http/routers | jq
   
   # Check middleware status
   curl -s http://localhost:8081/api/http/middlewares | jq
   
   # Test routing directly
   curl -H "Host: grafana.homelab.local" http://localhost
   ```

4. **Docker Network Debugging**:
   ```bash
   # List networks
   docker network ls
   
   # Inspect network
   docker network inspect bridge
   ```

### Resolving Common Issues

1. **Restoring DNS Configuration After DSM Update**:
   ```bash
   sudo mkdir -p /etc/dnsmasq.conf.d
   echo "server=/consul/127.0.0.1#8600" | sudo tee /etc/dnsmasq.conf.d/10-consul
   sudo systemctl restart dnsmasq
   ```

2. **Fixing Certificate Trust Issues**:
   ```bash
   # Export certificate
   cp /volume1/docker/nomad/config/certs/homelab.crt /volume1/public/
   
   # Download and install on client devices
   ```

3. **Resolving Port Conflicts**:
   ```bash
   # Find what's using a port
   sudo lsof -i :<port>
   
   # Change service port in configuration
   # Edit jobs/<service>.hcl
   ```