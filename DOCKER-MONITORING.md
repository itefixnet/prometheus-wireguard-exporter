# Docker Container Monitoring Examples

This document shows how to monitor WireGuard running in Docker containers.

## Quick Start

### Find Your Container

```bash
# List all running containers
docker ps

# List only names
docker ps --format '{{.Names}}'

# Check if WireGuard is in a specific container
docker exec <container-name> wg show
```

### Monitor Container

```bash
# Export container name
export WIREGUARD_DOCKER_CONTAINER=wireguard

# Test connectivity
./wireguard-exporter.sh test

# Collect metrics
./wireguard-exporter.sh collect

# Start HTTP server
./http-server.sh start
```

## Common Container Setups

### LinuxServer.io WireGuard Container

```bash
# Typical container name
export WIREGUARD_DOCKER_CONTAINER=wireguard

# Or full name if using docker-compose
export WIREGUARD_DOCKER_CONTAINER=myproject_wireguard_1
```

### Custom WireGuard Container

```bash
# Find your container
docker ps --filter "ancestor=linuxserver/wireguard"

# Set the name
export WIREGUARD_DOCKER_CONTAINER=your_container_name
```

## Configuration Files

### Using config.sh

```bash
# Edit config.sh
cat >> config.sh <<EOF
export WIREGUARD_DOCKER_CONTAINER="wireguard"
EOF

# The exporter will automatically use this
./wireguard-exporter.sh test
```

### Using wireguard-exporter.conf (for systemd)

```bash
# Edit /opt/wireguard-exporter/wireguard-exporter.conf
WIREGUARD_DOCKER_CONTAINER=wireguard
WIREGUARD_INTERFACE=wg0

# Restart service
sudo systemctl restart wireguard-exporter
```

## Systemd Service with Docker

When running as a systemd service, ensure the service has access to Docker:

```ini
[Service]
Type=simple
User=root  # Or user in docker group
Group=docker
EnvironmentFile=/opt/wireguard-exporter/wireguard-exporter.conf
# ... rest of service config
```

Or add the exporter user to docker group:

```bash
sudo usermod -aG docker wireguard-exporter
sudo systemctl daemon-reload
sudo systemctl restart wireguard-exporter
```

## Example: Monitor Multiple Containers

```bash
# Container 1
WIREGUARD_DOCKER_CONTAINER=wireguard-vpn1 \
  LISTEN_PORT=9586 \
  ./http-server.sh start &

# Container 2
WIREGUARD_DOCKER_CONTAINER=wireguard-vpn2 \
  LISTEN_PORT=9587 \
  ./http-server.sh start &

# Both exporters run on different ports
curl http://localhost:9586/metrics  # Container 1
curl http://localhost:9587/metrics  # Container 2
```

## Prometheus Configuration

```yaml
scrape_configs:
  - job_name: 'wireguard-docker'
    static_configs:
      - targets: ['localhost:9586']
        labels:
          container: 'wireguard-vpn1'
      - targets: ['localhost:9587']
        labels:
          container: 'wireguard-vpn2'
```

## Troubleshooting

### Test Docker Access

```bash
# Can you execute commands in the container?
docker exec wireguard echo "test"

# Can you run wg in the container?
docker exec wireguard wg --version

# Can you see interfaces?
docker exec wireguard wg show
```

### Permission Issues

```bash
# Add your user to docker group
sudo usermod -aG docker $USER

# Log out and back in, then test
docker ps

# Or run with sudo (not recommended for production)
sudo WIREGUARD_DOCKER_CONTAINER=wireguard ./wireguard-exporter.sh test
```

### Container Not Found

```bash
# List all containers (including stopped)
docker ps -a

# Check if container name is correct
docker inspect wireguard | grep Name

# Try with container ID instead
docker ps --format '{{.ID}} {{.Names}}'
export WIREGUARD_DOCKER_CONTAINER=<container-id>
```

### WireGuard Not in Container

```bash
# Check what's installed in container
docker exec wireguard which wg
docker exec wireguard apk list | grep wireguard  # Alpine
docker exec wireguard dpkg -l | grep wireguard   # Debian/Ubuntu

# Install if missing (Alpine example)
docker exec wireguard apk add wireguard-tools
```

## Security Considerations

### Docker Socket Access

The exporter needs access to Docker socket (`/var/run/docker.sock`). Be aware:

- User must be in `docker` group or run as root
- Docker group has root-equivalent privileges
- Consider using Docker API with TLS for remote monitoring

### Alternative: Run Exporter Inside Container

If you prefer not to give Docker socket access:

1. Copy exporter scripts into the WireGuard container
2. Run exporter inside the container
3. Expose port 9586 from container

```bash
docker cp wireguard-exporter.sh wireguard:/usr/local/bin/
docker cp http-server.sh wireguard:/usr/local/bin/
docker exec -d wireguard /usr/local/bin/http-server.sh start
```

## Advanced: Docker API

For remote Docker hosts:

```bash
# Set Docker host
export DOCKER_HOST=tcp://remote-host:2376
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH=/path/to/certs

# Then use normally
export WIREGUARD_DOCKER_CONTAINER=wireguard
./wireguard-exporter.sh test
```
