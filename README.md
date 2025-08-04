# Apache Pulsar Service

This repository contains a Docker Compose setup for running Apache Pulsar with ZooKeeper, BookKeeper, and Pulsar Manager.

## Prerequisites

- Docker Desktop for Windows
- Git Bash or similar bash shell

## Quick Start

1. **Install Docker** (if not already installed):
   ```bash
   ./install-docker.sh
   ```

2. **Start the Pulsar service**:
   ```bash
   ./run-service.sh
   ```

The script will automatically:
- Create required data directories (`data/zookeeper`, `data/bookkeeper`, `logs`)
- Pull the latest Docker images
- Start all Pulsar services
- Check service health
- Display service URLs and status

## Service URLs

Once started, you can access:

- **Pulsar Broker**: http://localhost:8080
- **Pulsar Admin REST API**: http://localhost:8080/admin/v2
- **Pulsar Manager**: http://localhost:9527
- **Pulsar Service URL**: pulsar://localhost:6650

### Pulsar Manager Credentials

- Username: `pulsar`
- Password: `pulsar`

## Useful Commands

### View service status:
```bash
docker compose ps
```

### View logs for a specific service:
```bash
docker logs broker -f
docker logs zookeeper -f
docker logs bookie -f
```

### Stop services:
```bash
docker compose down
```

### Restart a specific service:
```bash
docker compose restart broker
```

### Clean up everything (removes all data):
```bash
./docker_cleanup.sh
```

## Troubleshooting

### Common Issues

1. **ZooKeeper data directory error**: 
   - The `run-service.sh` script automatically creates required directories
   - If you encounter permission issues, try running as administrator

2. **Docker not running**:
   - Make sure Docker Desktop is started
   - Check if Docker daemon is running: `docker info`

3. **Port conflicts**:
   - Make sure ports 6650, 8080, and 9527 are not in use
   - Check with: `netstat -an | grep -E "(6650|8080|9527)"`

4. **Services not starting**:
   - Check logs: `docker logs <service-name>`
   - Restart services: `docker compose restart`

### Reset Everything

If you encounter persistent issues:

1. Stop and remove all containers:
   ```bash
   docker compose down --volumes --remove-orphans
   ```

2. Clean up Docker system:
   ```bash
   ./docker_cleanup.sh
   ```

3. Remove data directories:
   ```bash
   rm -rf data/ logs/
   ```

4. Start fresh:
   ```bash
   ./run-service.sh
   ```

## Architecture

This setup includes:

- **ZooKeeper**: Metadata storage and coordination
- **BookKeeper**: Message storage
- **Pulsar Broker**: Message routing and APIs
- **Pulsar Manager**: Web-based management UI

## Data Persistence

Data is persisted in local directories:
- `data/zookeeper/`: ZooKeeper data
- `data/bookkeeper/`: BookKeeper ledger data
- `logs/`: Service logs (optional)

These directories are excluded from version control via `.gitignore`.
