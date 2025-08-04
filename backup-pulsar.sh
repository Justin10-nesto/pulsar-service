#!/bin/bash

set -e

BACKUP_DIR="./backup/$(date +%Y%m%d_%H%M%S)"
BACKUP_RETENTION_DAYS=30

echo "=== Apache Pulsar Backup Script ==="
echo "Backup directory: $BACKUP_DIR"
echo "Date: $(date)"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "1. Backing up configuration files..."
cp -r .env* "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.yml "$BACKUP_DIR/"
cp *.sh "$BACKUP_DIR/" 2>/dev/null || true
echo "✓ Configuration files backed up"

echo ""
echo "2. Backing up ZooKeeper metadata..."
if docker exec zookeeper bin/pulsar zookeeper-shell -server zookeeper:2181 <<< "ls /" > "$BACKUP_DIR/zookeeper_metadata.txt" 2>/dev/null; then
    echo "✓ ZooKeeper metadata backed up"
else
    echo "⚠️  Warning: Could not backup ZooKeeper metadata"
fi

echo ""
echo "3. Backing up topic metadata..."
if docker exec broker bin/pulsar-admin namespaces list > "$BACKUP_DIR/namespaces.txt" 2>/dev/null; then
    echo "✓ Namespace list backed up"
fi

if docker exec broker bin/pulsar-admin topics list-partitioned-topics public > "$BACKUP_DIR/partitioned_topics.txt" 2>/dev/null; then
    echo "✓ Partitioned topics list backed up"
fi

echo ""
# Create data volume backups
echo "4. Creating data volume backups..."
# Use absolute Windows paths for volume mounts
BACKUP_MOUNT_PATH="$(cd "$SCRIPT_DIR/backup/$BACKUP_DIR" && pwd)"
docker run --rm -v pulsar-service_zookeeper-data:/volume -v "$BACKUP_MOUNT_PATH":/backup busybox tar czf /backup/zookeeper-data.tar.gz -C /volume .
docker run --rm -v pulsar-service_bookkeeper-data:/volume -v "$BACKUP_MOUNT_PATH":/backup busybox tar czf /backup/bookkeeper-data.tar.gz -C /volume .
docker run --rm -v pulsar-service_pulsar-data:/volume -v "$BACKUP_MOUNT_PATH":/backup busybox tar czf /backup/pulsar-data.tar.gz -C /volume .echo ""
echo "5. Creating backup manifest..."
cat > "$BACKUP_DIR/backup_manifest.txt" << EOF
Pulsar Backup Manifest
=====================
Backup Date: $(date)
Backup Directory: $BACKUP_DIR
Docker Compose Project: $(basename $(pwd))

Services backed up:
- ZooKeeper (metadata + data)
- BookKeeper (data)
- Broker (configuration)
- Pulsar Manager (data)

Files included:
- Configuration files (.env*, docker-compose.yml, scripts)
- ZooKeeper metadata export
- Topic and namespace listings
- Complete data volume backups

Restore instructions:
1. Stop current services: docker compose down -v
2. Extract data volumes: 
   - docker volume create pulsar-service_zookeeper-data
   - docker volume create pulsar-service_bookkeeper-data  
   - docker volume create pulsar-service_pulsar-data
3. Restore data:
   - docker run --rm -v pulsar-service_zookeeper-data:/target -v $(pwd):/backup alpine tar xzf /backup/zookeeper-data.tar.gz -C /target
   - docker run --rm -v pulsar-service_bookkeeper-data:/target -v $(pwd):/backup alpine tar xzf /backup/bookkeeper-data.tar.gz -C /target
   - docker run --rm -v pulsar-service_pulsar-data:/target -v $(pwd):/backup alpine tar xzf /backup/pulsar-data.tar.gz -C /target
4. Restore configuration: cp .env* docker-compose.yml ../
5. Start services: docker compose up -d
EOF

echo "✓ Backup manifest created"

echo ""
echo "6. Cleaning up old backups..."
if [ -d "./backup" ]; then
    find ./backup -type d -name "*_*" -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true
    echo "✓ Old backups cleaned (keeping last $BACKUP_RETENTION_DAYS days)"
fi

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

echo ""
echo "🎉 Backup completed successfully!"
echo "Backup location: $BACKUP_DIR"
echo "Backup size: $BACKUP_SIZE"
echo ""
echo "To restore this backup:"
echo "  ./restore-pulsar.sh $BACKUP_DIR"
