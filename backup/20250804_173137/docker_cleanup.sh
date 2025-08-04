#!/bin/bash

# Stop all running containers
docker stop $(docker ps -q)

# Remove all containers
docker rm $(docker ps -aq)

# Remove all images
docker rmi $(docker images -q) --force

# Remove all volumes
docker volume rm $(docker volume ls -q)

# Prune unused volumes (optional)
docker volume prune -f

# Remove all networks
docker network rm $(docker network ls -q)

# Prune unused networks (optional)
docker network prune -f

# Clear the Docker system
docker system prune -a --volumes -f

echo "Docker cleanup completed!"
