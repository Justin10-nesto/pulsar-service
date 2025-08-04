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
echo -n "Broker Port 6650: "
if nc -z "${PULSAR_BROKER_IP:-localhost}" 6650 2>/dev/null; then
    echo "✓ Open"
else
    echo "❌ Closed"
fi

echo -n "HTTP Port 8080: "
if nc -z "${PULSAR_BROKER_IP:-localhost}" 8080 2>/dev/null; then
    echo "✓ Open"
else
    echo "❌ Closed"
fi

echo -n "Manager Port 9527: "
if nc -z "${PULSAR_BROKER_IP:-localhost}" 9527 2>/dev/null; then
    echo "✓ Open"
else
    echo "❌ Closed"
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
