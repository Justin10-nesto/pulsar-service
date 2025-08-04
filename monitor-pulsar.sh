#!/bin/bash

echo "=== Apache Pulsar Production Monitoring ==="
echo "Date: $(date)"
echo ""

# Load environment
if [ -f ".env" ]; then
    source .env
fi

echo "1. Service Health Status:"
echo "========================="
docker compose ps

echo ""
echo "2. Resource Usage:"
echo "=================="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"

echo ""
echo "3. Pulsar Cluster Status:"
echo "========================="

# Check broker status
echo -n "Broker Status: "
if curl -s "http://${PULSAR_BROKER_IP:-localhost}:8080/admin/v2/brokers/health" >/dev/null 2>&1; then
    echo "✓ Healthy"
else
    echo "❌ Unhealthy"
fi

# Check topic stats
echo ""
echo "Active Topics:"
docker exec broker bin/pulsar-admin topics list public/default 2>/dev/null | wc -l | xargs echo "Count:"

# Check namespaces
echo ""
echo "Namespaces:"
docker exec broker bin/pulsar-admin namespaces list 2>/dev/null | sed 's/^/  - /'

echo ""
echo "4. Storage Usage:"
echo "================="

# Check volume usage
echo "Docker Volumes:"
docker volume ls --format "table {{.Name}}\t{{.Driver}}" | grep pulsar-service

echo ""
echo "Volume Sizes:"
for volume in $(docker volume ls --format "{{.Name}}" | grep pulsar-service); do
    size=$(docker run --rm -v "$volume":/data alpine du -sh /data 2>/dev/null | cut -f1)
    echo "  $volume: $size"
done

echo ""
echo "5. Recent Errors (Last 10 lines):"
echo "=================================="
echo "ZooKeeper errors:"
docker logs zookeeper --since=1h 2>&1 | grep -i error | tail -5 || echo "  No recent errors"

echo ""
echo "BookKeeper errors:"
docker logs bookie --since=1h 2>&1 | grep -i error | tail -5 || echo "  No recent errors"

echo ""
echo "Broker errors:"
docker logs broker --since=1h 2>&1 | grep -i error | tail -5 || echo "  No recent errors"

echo ""
echo "6. Performance Metrics:"
echo "======================="

# Check if broker is responding to admin API
echo -n "Admin API Response Time: "
start_time=$(date +%s%N)
if curl -s "http://${PULSAR_BROKER_IP:-localhost}:8080/admin/v2/brokers/health" >/dev/null 2>&1; then
    end_time=$(date +%s%N)
    duration=$(((end_time - start_time) / 1000000))
    echo "${duration}ms"
else
    echo "Failed"
fi

# Memory usage details
echo ""
echo "Container Memory Details:"
docker exec broker cat /proc/meminfo 2>/dev/null | grep -E "(MemTotal|MemFree|MemAvailable)" | sed 's/^/  /' || echo "  Unable to get memory info"

echo ""
echo "7. Network Connectivity:"
echo "========================"

# Get the IP from .env file
BROKER_IP="${PULSAR_BROKER_IP:-localhost}"
USE_PUBLIC_IP=""
if [ -f ".env" ]; then
    USE_PUBLIC_IP=$(grep "^USE_PUBLIC_IP=" .env 2>/dev/null | cut -d'=' -f2)
fi

echo "Testing connectivity to: $BROKER_IP"

# Test broker HTTP API (more reliable than port scanning)
echo -n "HTTP Port 8080: "
if curl -s --connect-timeout 5 "http://$BROKER_IP:8080/admin/v2/brokers/health" >/dev/null 2>&1; then
    echo "✅ Healthy"
    
    # Get response time
    RESPONSE_TIME=$(curl -w "%{time_total}" -s -o /dev/null --connect-timeout 5 "http://$BROKER_IP:8080/admin/v2/brokers/health" 2>/dev/null || echo "0")
    RESPONSE_MS=$(echo "$RESPONSE_TIME * 1000" | bc 2>/dev/null | cut -d. -f1 || echo "N/A")
    echo "  Response time: ${RESPONSE_MS}ms"
else
    echo "❌ Not accessible"
fi

# Test Pulsar service port using netcat with timeout
echo -n "Broker Port 6650: "
if command -v nc >/dev/null 2>&1; then
    if nc -z -w 3 "$BROKER_IP" 6650 2>/dev/null; then
        echo "✅ Open"
    else
        echo "⚠️  Not reachable (may be normal for external IPs)"
    fi
else
    # Alternative method for systems without nc
    if timeout 3 bash -c "</dev/tcp/$BROKER_IP/6650" 2>/dev/null; then
        echo "✅ Open"
    else
        echo "⚠️  Not testable without netcat"
    fi
fi

# Test Pulsar Manager
echo -n "Manager Port 9527: "
if curl -s --connect-timeout 5 -I "http://$BROKER_IP:9527" >/dev/null 2>&1; then
    echo "✅ Accessible"
else
    echo "❌ Not accessible"
fi

# Additional connectivity information
echo ""
echo "Service URLs:"
echo "  Broker Admin:    http://$BROKER_IP:8080"
echo "  Pulsar Service:  pulsar://$BROKER_IP:6650"
echo "  Pulsar Manager:  http://$BROKER_IP:9527"

if [ "$USE_PUBLIC_IP" = "true" ]; then
    echo ""
    echo "🌐 Public IP Configuration Active"
    echo "⚠️  For external access, ensure firewall allows:"
    echo "   - Port 6650 (Pulsar broker service)"
    echo "   - Port 8080 (Admin API & HTTP)"
    echo "   - Port 9527 (Pulsar Manager web UI)"
else
    echo ""
    echo "🏠 Private IP Configuration (Local/Internal Access)"
    echo "💡 To enable external access: set USE_PUBLIC_IP=true in .env"
fi

echo ""
echo "8. Recommendations:"
echo "==================="

# Check for issues and provide recommendations
total_containers=$(docker compose ps | wc -l)
healthy_containers=$(docker compose ps | grep "Up" | wc -l)

if [ "$healthy_containers" -lt "$total_containers" ]; then
    echo "⚠️  Some containers are not running. Check logs and restart if needed."
fi

# Check memory usage
memory_usage=$(docker stats --no-stream --format "{{.MemPerc}}" broker 2>/dev/null | sed 's/%//')
if [ ! -z "$memory_usage" ] && [ "${memory_usage%.*}" -gt 80 ]; then
    echo "⚠️  High memory usage detected (${memory_usage}%). Consider increasing memory allocation."
fi

# Check disk space
available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$available_space" -lt 5 ]; then
    echo "⚠️  Low disk space (${available_space}GB remaining). Consider cleanup or expansion."
fi

echo ""
echo "Monitor completed at $(date)"
echo ""
echo "For continuous monitoring, run:"
echo "  watch -n 30 ./monitor-pulsar.sh"
