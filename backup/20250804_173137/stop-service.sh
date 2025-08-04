#!/bin/bash

set -e  # Exit on any error

echo "=== Apache Pulsar Service Stop Script ==="
echo "Current directory: $(pwd)"
echo "Date: $(date)"
echo ""

# Check if Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    if ! docker-compose --version >/dev/null 2>&1; then
        echo "❌ Error: Docker Compose is not available."
        exit 1
    else
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

echo "1. Stopping Apache Pulsar services..."
$DOCKER_COMPOSE_CMD down

echo ""
echo "2. Checking for any remaining containers..."
REMAINING_CONTAINERS=$(docker ps -a --filter name=zookeeper --filter name=broker --filter name=bookie --filter name=pulsar-manager --filter name=pulsar-init --format "{{.Names}}" 2>/dev/null || true)

if [ ! -z "$REMAINING_CONTAINERS" ]; then
    echo "Found remaining containers, removing them:"
    echo "$REMAINING_CONTAINERS"
    docker rm $REMAINING_CONTAINERS 2>/dev/null || true
fi

echo ""
echo "✅ Apache Pulsar services stopped successfully!"
echo ""
echo "Data is preserved in the 'data/' directory."
echo "To restart the services, run: ./run-service.sh"
echo "To completely clean up (remove all data), run: ./docker_cleanup.sh"
