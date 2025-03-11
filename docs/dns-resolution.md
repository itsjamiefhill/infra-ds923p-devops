# DNS Resolution in HomeLab DevOps Platform

This document explains the different DNS resolution methods available in the HomeLab DevOps Platform and how to implement them in your Synology environment.

## Table of Contents

1. [Overview](#overview)
2. [DNS Requirements](#dns-requirements)
3. [Resolution Methods](#resolution-methods)
   - [Hosts File Method](#hosts-file-method)
   - [dnsmasq Integration](#dnsmasq-integration)
   - [Router-Based DNS](#router-based-dns)
   - [Dedicated DNS Server](#dedicated-dns-server)
4. [Synology-Specific Considerations](#synology-specific-considerations)
5. [Service Names and Domains](#service-names-and-domains)
6. [Testing DNS Resolution](#testing-dns-resolution)
7. [Troubleshooting](#troubleshooting)

## Overview

The HomeLab DevOps Platform relies on DNS resolution for service discovery and access. Proper DNS resolution allows you to:

- Access services by consistent domain names
- Enable Consul DNS-based service discovery
- Access the web interfaces of platform components
- Allow applications to discover each other

## DNS Requirements

For a fully functional platform, you need DNS resolution for:

1. **Static Service Domains**: Fixed domain names for accessing components
   - Example: `grafana.homelab.local`, `vault.homelab.local`

2. **Consul Service Discovery**: Dynamic resolution of service registrations
   - Example: `service-name.service.consul`

3. **Internal Services**: Backend services that don't require external access
   - Example: `postgres.service.consul`, `loki.service.consul`

## Resolution Methods

### Hosts File Method

The simplest approach is to add entries to your system's hosts file:

**Advantages**:
- Simple to implement
- Works on any system
- No additional software required

**Disadvantages**:
- Must be manually updated for new services
- Must be configured on each client device
- Doesn't handle dynamic service discovery

**Implementation**:

1. On the Synology NAS:
   ```bash
   # For static services
   echo "10.0.4.78 consul.homelab.local" | sudo tee -a /etc/hosts
   echo "10.0.4.78 traefik.homelab.local" | sudo tee -a /etc/hosts
   
   # For Consul service discovery
   echo "10.0.4.78 consul.service.consul" | sudo tee -a /etc/hosts
   ```

2. On client computers:
   - Windows: Edit `C:\Windows\System32\drivers\etc\hosts`
   - macOS/Linux: Edit `/etc/hosts`
   - Add the same entries as above

### dnsmasq Integration

dnsmasq can provide local DNS resolution and forwarding:

**Advantages**:
- Dynamic resolution for Consul services
- Centralized configuration
- Lightweight and efficient

**Disadvantages**:
- Not available on all Synology models by default
- May be reset during DSM updates
- Requires additional configuration

**Implementation**:

1. Check if dnsmasq is available:
   ```bash
   command -v dnsmasq
   ```

2. If available, create configuration:
   ```bash
   sudo mkdir -p /etc/dnsmasq.conf.d
   echo "server=/consul/127.0.0.1#8600" | sudo tee /etc/dnsmasq.conf.d/10-consul
   ```

3. Restart dnsmasq (if possible):
   ```bash
   sudo systemctl restart dnsmasq 2>/dev/null || true
   ```

### Router-Based DNS

Use your network router to handle DNS resolution:

**Advantages**:
- Works for all devices on the network
- No client configuration needed
- Can be centrally managed

**Disadvantages**:
- Router must support custom DNS configuration
- May not support forwarding specific domains
- Configuration interface varies by router model

**Implementation**:

1. Access your router's administration interface
2. Look for DNS or DHCP settings
3. Configure domain forwarding:
   - Forward `.homelab.local` to your Synology IP (10.0.4.78)
   - Forward `.consul` to your Synology IP (10.0.4.78)
4. If your router supports dnsmasq:
   ```
   server=/homelab.local/10.0.4.78
   server=/consul/10.0.4.78
   ```

### Dedicated DNS Server

Run a dedicated DNS server (like Pi-hole, dnsmasq, or BIND):

**Advantages**:
- Most flexible and powerful solution
- Can handle complex configurations
- Provides additional features (caching, filtering)

**Disadvantages**:
- Requires additional hardware or resources
- More complex to set up and maintain
- May create a single point of failure

**Implementation**:

1. Set up a DNS server (e.g., Pi-hole on a Raspberry Pi)
2. Configure forwarding:
   ```
   server=/homelab.local/10.0.4.78
   server=/consul/10.0.4.78#8600
   ```
3. Configure your router's DHCP to use this DNS server
4. Or configure clients to use this DNS server directly

## Synology-Specific Considerations

Synology DSM has some unique characteristics regarding DNS:

1. **DSM Updates**: DNS configurations may be reset during updates
   - Solution: Create a backup and restore script

2. **Default DNS**: Synology uses its own DNS configuration
   - Check current DNS settings in Control Panel > Network

3. **Package Availability**: Some models/DSM versions may not have dnsmasq
   - Alternative: Use hosts file or external DNS solution

4. **Network Manager**: DSM uses a custom network management system
   - Some standard Linux network commands may not work as expected

## Service Names and Domains

The platform uses specific naming conventions:

1. **Web UI Access**:
   - Format: `service-name.homelab.local`
   - Examples: `consul.homelab.local`, `grafana.homelab.local`
   - Resolved via hosts file or router DNS

2. **Consul Service Discovery**:
   - Format: `service-name.service.consul`
   - Examples: `consul.service.consul`, `postgres.service.consul`
   - Resolved via Consul DNS or hosts file

3. **Internal Services**:
   - Format: `service-name:port`
   - Examples: `localhost:8500`, `10.0.4.78:3000`
   - Direct IP access when DNS not needed

## Testing DNS Resolution

To test if your DNS resolution is working:

### Basic Host Resolution

```bash
# Using ping
ping consul.homelab.local

# Using curl
curl -v http://consul.homelab.local:8500/ui/
```

### Consul DNS Resolution

```bash
# Direct query to Consul DNS (should work regardless of DNS setup)
dig @127.0.0.1 -p 8600 consul.service.consul

# Testing hosts file resolution
ping consul.service.consul

# Using alternative tools if dig is not available
sudo docker run --rm --network host alpine sh -c "apk add --no-cache bind-tools && dig @127.0.0.1 -p 8600 consul.service.consul"
```

### Testing via Web Browser

1. Open your browser
2. Navigate to `http://consul.homelab.local:8500`
3. You should see the Consul UI

## Troubleshooting

### Common DNS Issues

1. **Cannot Resolve Service Names**:
   - Check hosts file entries
   - Verify router DNS configuration
   - Test direct IP access to isolate DNS issues

2. **dnsmasq Not Working**:
   - Verify dnsmasq is installed
   - Check configuration files
   - Test with direct query to Consul DNS

3. **Intermittent Resolution**:
   - DNS caching issues - clear cache or reduce TTL
   - Multiple DNS servers with different configurations
   - Check for conflicting entries

### Checking Configurations

```bash
# Hosts file
cat /etc/hosts | grep homelab
cat /etc/hosts | grep consul

# dnsmasq config
cat /etc/dnsmasq.conf.d/10-consul

# Current DNS server
cat /etc/resolv.conf

# Testing direct resolution
curl -v http://10.0.4.78:8500/ui/
```

### DNS Resolution Flow

The platform attempts DNS resolution in this order:

1. Check hosts file first
2. Query local dnsmasq if available
3. Forward to Consul DNS for .consul domains
4. Fall back to standard DNS resolution

Understanding this flow helps identify where resolution is failing.

### Alternative Testing Methods

If standard DNS tools are not available on your Synology:

1. **Using Docker**:
   ```bash
   sudo docker run --rm alpine sh -c "apk add --no-cache bind-tools && dig @10.0.4.78 -p 8600 consul.service.consul"
   ```

2. **Using curl with verbose output**:
   ```bash
   curl -v http://consul.service.consul:8500/ui/
   ```

3. **Using wget**:
   ```bash
   wget -O- http://consul.service.consul:8500/v1/catalog/services
   ```