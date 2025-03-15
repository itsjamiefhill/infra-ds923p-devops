# 5. troubleshooting/network.md
# Network and SSL Troubleshooting

This document covers network-related issues, including DNS resolution, certificate problems, Nomad SSL configuration, and port conflicts.

## Table of Contents

1. [DNS Resolution Problems](#dns-resolution-problems)
2. [Certificate Issues](#certificate-issues)
3. [Nomad SSL Configuration](#nomad-ssl-configuration)
4. [Port Conflicts](#port-conflicts)
5. [Network Interface Issues](#network-interface-issues)

## DNS Resolution Problems

### Consul DNS Integration Issues

If services cannot resolve `.consul` domains:

1. Test Consul DNS directly:
   ```bash
   dig @127.0.0.1 -p 8600 consul.service.consul
   ```

2. Check if Docker containers can resolve:
   ```bash
   docker run --rm --network host alpine sh -c "apk add --no-cache bind-tools && dig @127.0.0.1 -p 8600 consul.service.consul"
   ```

3. Check hosts file entries:
   ```bash
   cat /etc/hosts | grep consul
   ```

4. Add entries to hosts file if needed:
   ```bash
   # Add an entry for consul.service.consul
   sudo grep -q "consul.service.consul" /etc/hosts || \
     echo "$(hostname -I | awk '{print $1}') consul.service.consul" | sudo tee -a /etc/hosts
   ```

### Custom Domain Resolution

If your custom domains (like homelab.local) aren't resolving:

1. Check hosts file entries:
   ```bash
   cat /etc/hosts | grep homelab.local
   ```

2. Add entries if needed:
   ```bash
   echo "10.0.4.78 traefik.homelab.local" | sudo tee -a /etc/hosts
   echo "10.0.4.78 vault.homelab.local" | sudo tee -a /etc/hosts
   ```

3. Check your router's DNS configuration if applicable.

### DNS Cache Issues

If DNS changes aren't taking effect:

1. Clear DNS cache on Synology:
   ```bash
   sudo killall -HUP nscd
   ```

2. For client machines, clear their DNS cache:
   - Windows: `ipconfig /flushdns`
   - macOS: `sudo killall -HUP mDNSResponder`
   - Linux: `sudo systemd-resolve --flush-caches`

## Certificate Issues

### Self-Signed Certificate Errors

If browsers show certificate errors:

1. Check certificate validity:
   ```bash
   openssl x509 -in /volume1/docker/nomad/config/certs/homelab.crt -text -noout
   ```

2. Verify certificate expiration:
   ```bash
   openssl x509 -in /volume1/docker/nomad/config/certs/homelab.crt -noout -dates
   ```

3. Import certificate to your client device:
   - Windows: Import to "Trusted Root Certification Authorities"
   - macOS: Import to Keychain, set to "Always Trust"
   - Linux: Add to `/usr/local/share/ca-certificates/` and run `update-ca-certificates`
   - iOS/Android: Install profile/certificate via Settings

### Certificate Renewal

If certificates are expired or about to expire:

1. Generate new certificates:
   ```bash
   openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
     -keyout /volume1/docker/nomad/config/certs/homelab.key \
     -out /volume1/docker/nomad/config/certs/homelab.crt \
     -subj "/CN=*.homelab.local" \
     -addext "subjectAltName=DNS:*.homelab.local,DNS:homelab.local"
   ```

2. Update Traefik and other services to use the new certificates:
   ```bash
   # Copy to certificates volume
   cp /volume1/docker/nomad/config/certs/homelab.crt /volume1/docker/nomad/volumes/certificates/
   cp /volume1/docker/nomad/config/certs/homelab.key /volume1/docker/nomad/volumes/certificates/
   ```

3. Restart the affected services:
   ```bash
   nomad job restart traefik
   ```

### Certificate Path Issues

If services can't find the certificate files:

1. Check if certificates exist in the expected locations:
   ```bash
   ls -la /volume1/docker/nomad/config/certs/
   ls -la /volume1/docker/nomad/volumes/certificates/
   ```

2. Verify proper mounting in Traefik:
   ```bash
   TRAEFIK_ALLOC=$(nomad job allocs -job traefik -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec ${TRAEFIK_ALLOC} ls -la /etc/traefik/certs/
   ```

3. Update job definitions if paths are incorrect:
   ```hcl
   mount {
     type = "bind"
     source = "/volume1/docker/nomad/volumes/certificates"
     target = "/etc/traefik/certs"
     readonly = true
   }
   ```

## Nomad SSL Configuration

### Environment Variables for Nomad SSL

To communicate with Nomad over SSL, set these environment variables:

```bash
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
```

For scripts, include these at the beginning:

```bash
#!/bin/bash
# Set up Nomad SSL environment
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem

# Load token
if [ -f "/volume1/docker/nomad/config/nomad_auth.conf" ]; then
  source "/volume1/docker/nomad/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi

# Now run Nomad commands
nomad job status
```

### Missing SSL Certificates

If Nomad SSL certificates are missing:

1. Check if certificates exist:
   ```bash
   ls -la /var/packages/nomad/shares/nomad/etc/certs/
   ```

2. If missing, you may need to reinstall Nomad with SSL enabled or recover from backup.

### Certificate Verification Failed

If you see "certificate verification failed" errors:

1. Verify certificate files are accessible:
   ```bash
   ls -la $NOMAD_CACERT $NOMAD_CLIENT_CERT $NOMAD_CLIENT_KEY
   ```

2. Check certificate validity:
   ```bash
   openssl verify -CAfile $NOMAD_CACERT $NOMAD_CLIENT_CERT
   ```

3. Test direct connection with certificate:
   ```bash
   curl --cacert $NOMAD_CACERT --cert $NOMAD_CLIENT_CERT --key $NOMAD_CLIENT_KEY https://127.0.0.1:4646/v1/agent/members
   ```

4. For debugging only, bypass verification:
   ```bash
   curl -k https://127.0.0.1:4646/v1/agent/members
   ```

### Authentication with Nomad SSL

To authenticate to Nomad with SSL:

1. Store your token securely:
   ```bash
   # Create a secure config file for the token
   mkdir -p /volume1/docker/nomad/config
   echo 'NOMAD_TOKEN="your-management-token"' > /volume1/docker/nomad/config/nomad_auth.conf
   chmod 600 /volume1/docker/nomad/config/nomad_auth.conf
   ```

2. Source this file in scripts:
   ```bash
   if [ -f "/volume1/docker/nomad/config/nomad_auth.conf" ]; then
     source "/volume1/docker/nomad/config/nomad_auth.conf"
     export NOMAD_TOKEN
   fi
   ```

3. Test authentication:
   ```bash
   nomad job status
   ```

## Port Conflicts

### Service Port Conflicts

If services fail due to port conflicts:

1. Check what's using the port:
   ```bash
   sudo lsof -i :<port>
   sudo ss -tulpn | grep <port>
   ```

2. Change the port in your configuration:
   ```bash
   # Edit config/custom.conf
   TRAEFIK_HTTP_PORT=81  # Change from default 80
   ```

3. Redeploy the affected service:
   ```bash
   ./scripts/04-deploy-traefik.sh
   ```

### Nomad Port Conflicts

If Nomad's port 4646 is in use:

1. Check what's using the port:
   ```bash
   sudo lsof -i :4646
   ```

2. Edit the Nomad configuration:
   ```bash
   sudo vi /var/packages/nomad/var/chroot/etc/nomad-config.d/nomad.hcl
   ```

3. Update the ports section:
   ```hcl
   ports {
     http = 4647  # Change from 4646
   }
   ```

4. Restart Nomad:
   ```bash
   sudo systemctl restart nomad
   ```

5. Update NOMAD_ADDR:
   ```bash
   export NOMAD_ADDR=https://127.0.0.1:4647
   ```

## Network Interface Issues

### Multiple Network Interfaces

If services have trouble binding to the correct interface:

1. Identify your primary interface and IP:
   ```bash
   ip route get 1 | awk '{print $7;exit}'
   # or
   hostname -I | awk '{print $1}'
   ```

2. For Consul, specify the bind address:
   ```bash
   PRIMARY_IP=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null || hostname -I | awk '{print $1}')
   
   sudo docker run -d --name consul \
     --restart always \
     --network host \
     -v ${DATA_DIR}/consul_data:/consul/data \
     hashicorp/consul:1.15.4 \
     agent -server -bootstrap \
     -bind=$PRIMARY_IP \
     -advertise=$PRIMARY_IP \
     -client=0.0.0.0 \
     -ui
   ```

3. For other services, specify the bind address in their configuration:
   ```hcl
   # For Traefik
   args = [
     "--entryPoints.web.address=:80",
     "--entryPoints.websecure.address=:443",
     "--entryPoints.traefik.address=:8081",
   ]
   ```

### Cannot Access Service from Another Machine

If you can access services locally but not from other machines:

1. Check firewall settings:
   ```bash
   sudo iptables -L
   ```

2. Configure DSM firewall:
   - Control Panel > Security > Firewall
   - Allow required ports from your network

3. Verify that services are binding to all interfaces, not just localhost:
   ```bash
   # For Consul
   -client=0.0.0.0
   ```

4. Check if the SSL certificates have the correct domain names:
   ```bash
   openssl x509 -in /volume1/docker/nomad/config/certs/homelab.crt -text -noout | grep -A1 "Subject Alternative Name"
   ```
```
