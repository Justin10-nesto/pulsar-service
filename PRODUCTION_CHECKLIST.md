# Apache Pulsar Production Deployment Checklist

## Pre-Deployment Checklist

### System Requirements

- [ ] **Memory**: Minimum 4GB RAM (8GB+ recommended)
- [ ] **Storage**: Minimum 20GB free space (100GB+ recommended)
- [ ] **CPU**: Minimum 2 cores (4+ cores recommended)
- [ ] **Network**: Stable internet connection and open ports

### Required Ports

- [ ] **6650**: Pulsar broker service (binary protocol)
- [ ] **8080**: Pulsar HTTP admin API
- [ ] **9527**: Pulsar Manager web interface
- [ ] **2181**: ZooKeeper (internal communication)

### Security Configuration

- [ ] **Firewall**: Configure firewall rules for required ports
- [ ] **Users**: Create dedicated non-root user for Pulsar
- [ ] **Passwords**: Change default passwords in `.env.production`
- [ ] **SSL/TLS**: Configure SSL certificates (optional but recommended)
- [ ] **Authentication**: Enable authentication for production (set `PULSAR_AUTHENTICATION_ENABLED=true`)
- [ ] **Authorization**: Enable authorization for production (set `PULSAR_AUTHORIZATION_ENABLED=true`)

### Environment Configuration

- [ ] **IP Address**: Set correct `PULSAR_BROKER_IP` in `.env.production`
- [ ] **Cluster Name**: Set appropriate `PULSAR_CLUSTER_NAME`
- [ ] **Memory Settings**: Adjust memory allocation based on available resources
- [ ] **Log Levels**: Set appropriate log levels for production
- [ ] **Manager Password**: Set strong password for Pulsar Manager

## Deployment Steps

### 1. Initial Setup

```bash
# Clone/copy your pulsar-service directory to production server
# Navigate to the directory
cd /path/to/pulsar-service

# Copy and customize production environment
cp .env.production .env
nano .env  # Edit with your specific settings
```

### 2. Production Deployment

```bash
# Run production deployment script
./deploy-production.sh
```

### 3. Verify Deployment

- [ ] **Services Running**: All containers are up and healthy
- [ ] **Connectivity**: Can access broker on configured IP:6650
- [ ] **Admin API**: Can access admin API on IP:8080
- [ ] **Web Interface**: Can access Pulsar Manager on IP:9527
- [ ] **Topic Operations**: Can create/delete topics successfully

## Post-Deployment Configuration

### 1. Initial Configuration

```bash
# Create default namespace and topics if needed
docker exec broker bin/pulsar-admin namespaces create public/production
docker exec broker bin/pulsar-admin topics create persistent://public/production/test-topic
```

### 2. Set Up Monitoring

```bash
# Test monitoring script
./monitor-pulsar.sh

# Set up cron job for regular monitoring (optional)
# crontab -e
# Add: */5 * * * * /path/to/pulsar-service/monitor-pulsar.sh >> /var/log/pulsar-monitor.log 2>&1
```

### 3. Set Up Backup

```bash
# Test backup script
./backup-pulsar.sh

# Set up daily backup cron job
# crontab -e  
# Add: 0 2 * * * /path/to/pulsar-service/backup-pulsar.sh >> /var/log/pulsar-backup.log 2>&1
```

## Ongoing Maintenance

### Daily Tasks

- [ ] **Monitor Status**: Check service health and resource usage
- [ ] **Check Logs**: Review error logs for issues
- [ ] **Disk Space**: Monitor available disk space
- [ ] **Backup Status**: Verify daily backups are working

### Weekly Tasks

- [ ] **Performance Review**: Analyze performance metrics
- [ ] **Log Rotation**: Clean up old log files
- [ ] **Security Updates**: Check for and apply security updates
- [ ] **Backup Testing**: Test backup restoration process

### Monthly Tasks

- [ ] **Full System Review**: Comprehensive health check
- [ ] **Capacity Planning**: Review resource usage trends
- [ ] **Documentation Update**: Update documentation and procedures
- [ ] **Disaster Recovery Test**: Test full disaster recovery procedures

## Scaling and High Availability

### Horizontal Scaling

```bash
# Scale BookKeeper nodes
docker compose up -d --scale bookie=3

# Add multiple brokers (requires additional configuration)
# See Apache Pulsar documentation for multi-broker setup
```

### Load Balancing

- [ ] **External Load Balancer**: Configure nginx/HAProxy for broker endpoints
- [ ] **DNS Round Robin**: Set up DNS-based load balancing
- [ ] **Health Checks**: Configure load balancer health checks

### Backup and Recovery

- [ ] **Multiple Backup Locations**: Store backups in multiple locations
- [ ] **Automated Backups**: Set up automated backup scheduling
- [ ] **Recovery Testing**: Regularly test backup restoration
- [ ] **Disaster Recovery Plan**: Document complete disaster recovery procedures

## Troubleshooting Common Issues

### Service Won't Start

1. Check Docker logs: `docker logs <service-name>`
2. Verify port availability: `netstat -tulpn | grep :<port>`
3. Check disk space: `df -h`
4. Verify environment variables: `cat .env`

### Performance Issues

1. Monitor resource usage: `./monitor-pulsar.sh`
2. Check container stats: `docker stats`
3. Review configuration: Memory, CPU allocation
4. Analyze message throughput and latency

### Connectivity Issues

1. Test port connectivity: `telnet <ip> <port>`
2. Check firewall rules: `iptables -L` or `ufw status`
3. Verify IP configuration in `.env`
4. Check broker advertised listeners

### Data Loss Prevention

1. Ensure regular backups: `./backup-pulsar.sh`
2. Monitor replication settings
3. Use persistent volumes for data
4. Implement proper retention policies

## Security Best Practices

### Access Control

- [ ] **Network Segmentation**: Isolate Pulsar cluster in private network
- [ ] **Minimal Privileges**: Run services with minimal required privileges
- [ ] **Regular Updates**: Keep Docker images and host system updated
- [ ] **Audit Logging**: Enable comprehensive audit logging

### Authentication & Authorization

- [ ] **Enable Authentication**: Set `PULSAR_AUTHENTICATION_ENABLED=true`
- [ ] **Configure Providers**: Set up JWT, TLS, or other auth providers
- [ ] **Role-Based Access**: Implement proper role-based access control
- [ ] **Regular Review**: Regularly review and update access permissions

## Performance Optimization

### Memory Tuning

```bash
# Adjust memory settings in docker-compose.yml
# ZooKeeper: 512MB-1GB
# BookKeeper: 1-2GB  
# Broker: 2-4GB
# Pulsar Manager: 512MB
```

### Storage Optimization

- [ ] **SSD Storage**: Use SSD storage for better performance
- [ ] **Separate Volumes**: Use separate volumes for different data types
- [ ] **Compression**: Enable compression for ledger storage
- [ ] **Retention Policies**: Set appropriate message retention policies

### Network Optimization

- [ ] **Dedicated Network**: Use dedicated network interfaces
- [ ] **Bandwidth Monitoring**: Monitor network bandwidth usage
- [ ] **TCP Tuning**: Optimize TCP settings for high throughput
- [ ] **Load Balancing**: Implement proper load balancing strategies

---

## Quick Reference Commands

```bash
# Start production services
./deploy-production.sh

# Monitor system health
./monitor-pulsar.sh

# Create backup
./backup-pulsar.sh

# View service logs
docker logs broker -f

# Check service status
docker compose ps

# Scale services
docker compose up -d --scale bookie=3

# Update services
docker compose pull && docker compose up -d

# Stop services
docker compose down

# Complete shutdown with data removal
docker compose down -v
```

Remember: Always test changes in a staging environment before applying to production!
