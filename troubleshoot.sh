#!/bin/bash

echo "=== Apache Pulsar Troubleshooting Script ==="
echo "Date: $(date)"
echo ""

echo "1. System Information:"
echo "======================"
echo "OS: $(uname -a)"
echo "User: $(whoami)"
echo "UID: $(id -u), GID: $(id -g)"
echo "Groups: $(groups)"
echo ""

echo "2. Docker Information:"
echo "======================"
docker --version
docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "Docker Compose not found"
echo "Docker daemon status:"
docker info >/dev/null 2>&1 && echo "✓ Docker is running" || echo "❌ Docker is not running"
echo ""

echo "3. Directory Permissions:"
echo "========================="
echo "Current directory: $(pwd)"
ls -la .
echo ""
if [ -d "data" ]; then
    echo "Data directory:"
    ls -la data/
    echo ""
    if [ -d "data/zookeeper" ]; then
        echo "ZooKeeper data directory:"
        ls -la data/zookeeper/
        if [ -d "data/zookeeper/version-2" ]; then
            echo "ZooKeeper version-2 directory:"
            ls -la data/zookeeper/version-2/
        fi
    fi
    echo ""
    if [ -d "data/bookkeeper" ]; then
        echo "BookKeeper data directory:"
        ls -la data/bookkeeper/
    fi
else
    echo "❌ Data directory does not exist"
fi
echo ""

echo "4. Container Status:"
echo "===================="
docker ps -a --filter name=zookeeper --filter name=broker --filter name=bookie --filter name=pulsar

echo ""
echo "5. Container Logs (last 20 lines):"
echo "==================================="
for container in zookeeper broker bookie pulsar-manager; do
    if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        echo ""
        echo "--- $container logs ---"
        docker logs "$container" --tail 20 2>&1
    fi
done

echo ""
echo "6. Network Information:"
echo "======================="
docker network ls | grep pulsar || echo "No Pulsar networks found"

echo ""
echo "7. Volume Information:"
echo "======================"
docker volume ls | grep pulsar || echo "No Pulsar volumes found"

echo ""
echo "8. Available Disk Space:"
echo "========================"
df -h . 2>/dev/null || echo "Cannot check disk space"

echo ""
echo "9. SELinux Status (if applicable):"
echo "=================================="
if command -v getenforce >/dev/null 2>&1; then
    getenforce
else
    echo "SELinux not present/configured"
fi

echo ""
echo "10. Fix Suggestions:"
echo "==================="
echo "If you're seeing permission errors, try these commands:"
echo ""
echo "# Fix directory permissions:"
echo "sudo chown -R 10000:10000 data/"
echo "chmod -R 755 data/"
echo ""
echo "# Or make directories world-writable (less secure):"
echo "chmod -R 777 data/"
echo ""
echo "# Clean restart:"
echo "docker compose down --volumes"
echo "sudo rm -rf data/"
echo "./run-service-server.sh"
echo ""
echo "# If on SELinux system:"
echo "sudo setsebool -P container_manage_cgroup true"
echo "sudo chcon -Rt svirt_sandbox_file_t data/"
