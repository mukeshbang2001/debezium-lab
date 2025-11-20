# Setup on New Machine - Complete Guide

## Prerequisites on New Laptop

1. **Docker Desktop** installed and running
   ```bash
   docker --version
   docker-compose --version
   ```

2. **Git** installed (for cloning)
   ```bash
   git --version
   ```

3. **curl** installed (usually pre-installed)
   ```bash
   curl --version
   ```

4. **jq** (optional but recommended for JSON formatting)
   ```bash
   # macOS
   brew install jq
   
   # Ubuntu/Debian
   sudo apt-get install jq
   ```

---

## Method 1: Clone from GitHub (Once Pushed)

### Step 1: Clone Repository
```bash
cd ~/projects  # or your preferred directory

git clone https://github.com/mukeshbang2001/debezium-lab.git

cd debezium-lab
```

### Step 2: Run Automated Setup
```bash
./fresh-setup.sh
```

**That's it!** The script will:
- ✅ Check prerequisites
- ✅ Start Docker containers
- ✅ Initialize MongoDB replica set
- ✅ Register Kafka connectors
- ✅ Run a test
- ✅ Show you the results

**Expected Time:** 2-3 minutes

---

## Method 2: Manual File Copy (No Git)

### Step 1: Copy Files to New Laptop

**From your current laptop:**
```bash
# Create a tarball (excludes node_modules, .git, etc.)
cd /Users/mukesh.bang/projects
tar -czf debezium-lab.tar.gz \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='tmp/*' \
  debezium-lab/

# Copy to new laptop using scp, USB drive, or cloud storage
scp debezium-lab.tar.gz user@new-laptop-ip:~/Downloads/
```

**On your new laptop:**
```bash
# Extract
cd ~/projects  # or wherever you want it
tar -xzf ~/Downloads/debezium-lab.tar.gz

cd debezium-lab
```

### Step 2: Make Scripts Executable
```bash
chmod +x fresh-setup.sh
chmod +x setup-connectors.sh
chmod +x test-flow.sh
chmod +x init/run-mongo-ops.sh
```

### Step 3: Run Setup
```bash
./fresh-setup.sh
```

---

## What the Setup Script Does

The `fresh-setup.sh` script automatically:

1. ✅ Checks Docker is installed
2. ✅ Starts all Docker containers (Zookeeper, Kafka, MongoDB, Postgres, Connect)
3. ✅ Waits for services to be ready
4. ✅ Initializes MongoDB replica set (required for CDC)
5. ✅ Registers MongoDB source connector
6. ✅ Registers MongoDB audit sink connector
7. ✅ Runs a test (insert → update → verify audit trail)
8. ✅ Shows you the results with DIFF capture

**Total Time:** ~2-3 minutes

---

## Manual Setup (If Script Fails)

If the automated script doesn't work, follow these manual steps:

### 1. Start Docker Containers
```bash
docker-compose up -d
```

Wait 20 seconds for services to start.

### 2. Verify Containers Running
```bash
docker ps
```

You should see 5 containers:
- zookeeper
- kafka
- mongodb
- postgres
- connect

### 3. Initialize MongoDB Replica Set
```bash
docker exec mongodb mongosh --eval \
  "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"
```

Wait 10 seconds.

### 4. Verify Replica Set
```bash
docker exec mongodb mongosh --eval "rs.status().members[0].stateStr"
```

Should output: `PRIMARY`

### 5. Wait for Kafka Connect
```bash
# Keep checking until it responds
curl http://localhost:8083/
```

### 6. Register Connectors
```bash
./setup-connectors.sh
```

Or manually:
```bash
# Delete old connectors (if any)
curl -X DELETE http://localhost:8083/connectors/mongo-source
curl -X DELETE http://localhost:8083/connectors/mongo-audit-history

# Register MongoDB Source
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/mongo-source.json

# Register MongoDB Audit Sink
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/mongo-audit-history.json
```

### 7. Verify Connectors
```bash
curl -s http://localhost:8083/connectors/mongo-source/status | jq .
curl -s http://localhost:8083/connectors/mongo-audit-history/status | jq .
```

Both should show `"state": "RUNNING"`

---

## Run the Test

```bash
./test-flow.sh
```

Or manually:
```bash
# Insert
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 1, name: "Mukesh", city: "Hyd"})'

sleep 3

# Update
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 1}, {$set: {name: "Ritu"}})'

sleep 3

# Check audit trail (should show DIFF)
docker exec mongodb mongosh auditdb --eval \
  'db.changes.find({"documentKey._id": 1}).pretty()'
```

**Expected Result:** Audit trail shows `DIFF: {"name": "Ritu"}`

---

## Verification Checklist

Run these commands to verify everything is working:

```bash
# 1. All containers running
docker ps --format "table {{.Names}}\t{{.Status}}"

# 2. Kafka Connect healthy
curl -s http://localhost:8083/ | jq .

# 3. Connectors registered
curl -s http://localhost:8083/connectors | jq .

# 4. Connectors running
curl -s http://localhost:8083/connectors/mongo-source/status | \
  jq '{name, connector: .connector.state, task: .tasks[0].state}'

# 5. MongoDB replica set initialized
docker exec mongodb mongosh --eval "rs.status().members[0].stateStr"

# 6. Test data
docker exec mongodb mongosh shop --eval 'db.customers.countDocuments()'
docker exec mongodb mongosh auditdb --eval 'db.changes.countDocuments()'
```

---

## Troubleshooting

### Issue: "Docker not found"
```bash
# Install Docker Desktop for your OS
# macOS: https://www.docker.com/products/docker-desktop
# Linux: sudo apt-get install docker.io docker-compose
```

### Issue: "Permission denied" on scripts
```bash
chmod +x *.sh
```

### Issue: Containers not starting
```bash
# Check Docker is running
docker ps

# If Docker Desktop not running, start it first
# Then try again:
docker-compose up -d
```

### Issue: "MongoDB replica set not initialized"
```bash
docker exec mongodb mongosh --eval \
  "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"

sleep 10
```

### Issue: "Kafka Connect not responding"
```bash
docker restart connect
sleep 15
curl http://localhost:8083/
```

### Issue: "Connectors failed to start"
```bash
# Check logs
docker logs connect --tail 50

# Restart connectors
./setup-connectors.sh
```

### Issue: "Port already in use"
```bash
# Check what's using the ports
lsof -i :8083  # Kafka Connect
lsof -i :27017 # MongoDB
lsof -i :5432  # Postgres
lsof -i :9092  # Kafka

# Stop conflicting services or change ports in docker-compose.yml
```

---

## Quick Reference Commands

### Start/Stop
```bash
# Start everything
docker-compose up -d

# Stop everything
docker-compose down

# Stop and remove all data
docker-compose down -v
```

### View Logs
```bash
# All services
docker-compose logs

# Specific service
docker logs connect
docker logs mongodb

# Follow logs
docker logs -f connect
```

### Check Status
```bash
# All connectors
curl -s http://localhost:8083/connectors | jq .

# Specific connector
curl -s http://localhost:8083/connectors/mongo-source/status | jq .
```

### Access Databases
```bash
# MongoDB shell
docker exec -it mongodb mongosh

# Postgres shell
docker exec -it debezium-lab-postgres-1 psql -U test -d auditdb
```

---

## Complete Fresh Start

If you need to start completely fresh:

```bash
# Stop and remove everything
docker-compose down -v

# Remove any leftover data
rm -rf data/ volumes/

# Start fresh
./fresh-setup.sh
```

---

## Next Steps After Setup

1. **Read the documentation:**
   - `README.md` - Complete guide
   - `QUICKSTART.md` - 5-minute quick start
   - `TROUBLESHOOTING.md` - Problem solving

2. **Run more tests:**
   ```bash
   ./test-flow.sh
   ```

3. **Try manual operations:**
   ```bash
   docker exec mongodb mongosh shop
   # Then run MongoDB commands
   ```

4. **Monitor in real-time:**
   ```bash
   # Terminal 1: Monitor Kafka
   docker exec debezium-lab-kafka-1 kafka-console-consumer \
     --bootstrap-server kafka:9092 \
     --topic mongo.shop.customers
   
   # Terminal 2: Make changes in MongoDB
   docker exec mongodb mongosh shop
   ```

---

## Expected Output from fresh-setup.sh

You should see something like:

```
================================================
  Debezium Lab - Fresh Setup
  MongoDB CDC with Audit Trail (DIFFS Capture)
================================================

Step 1: Checking prerequisites...
✓ Docker found: Docker version 24.0.0
✓ Docker Compose found: Docker Compose version v2.20.0
✓ curl found
✓ jq found (optional but helpful)

Step 2: Starting Docker containers...
✓ Docker containers started

Step 3: Waiting for services to start (20 seconds)...

Step 4: Verifying containers...
✓ All containers running:
  - debezium-lab-zookeeper-1 (Up 20 seconds)
  - debezium-lab-kafka-1 (Up 20 seconds)
  - mongodb (Up 20 seconds)
  - debezium-lab-postgres-1 (Up 20 seconds)
  - connect (Up 20 seconds)

Step 5: Initializing MongoDB replica set...
✓ MongoDB replica set initialized (PRIMARY)

Step 6: Waiting for Kafka Connect to be ready...
✓ Kafka Connect is ready

Step 7: Registering connectors...
  Registering MongoDB Source Connector... ✓
  Registering MongoDB Audit Sink Connector... ✓

Step 8: Checking connector status...
✓ MongoDB Source Connector: RUNNING
✓ MongoDB Audit Sink Connector: RUNNING

Step 9: Running test...
  Inserting test document...
  Updating document (name change)...
  Updating document (location change)...
✓ Audit trail has 3 events

=== Audit Trail (showing DIFFS) ===

--- INSERT ---
Time: Wed Nov 20 2025 03:00:00 GMT+0000
Document: {"_id":1,"name":"Mukesh","location":"Hyd","department":"Engineering"}

--- UPDATE ---
Time: Wed Nov 20 2025 03:00:03 GMT+0000
DIFF (Changed Fields): {"name":"Ritu"}
Full Document After: {"_id":1,"name":"Ritu","location":"Hyd","department":"Engineering"}

--- UPDATE ---
Time: Wed Nov 20 2025 03:00:06 GMT+0000
DIFF (Changed Fields): {"location":"Bangalore","department":"Sales"}
Full Document After: {"_id":1,"name":"Ritu","location":"Bangalore","department":"Sales"}

================================================
  Setup Complete!
================================================

✅ All systems operational!
```

---

## Summary

**Easiest Method:**
1. Clone from GitHub: `git clone https://github.com/mukeshbang2001/debezium-lab.git`
2. Run setup: `./fresh-setup.sh`
3. Done! ✨

**Total Time:** 2-3 minutes

---

**For detailed information, see README.md or TROUBLESHOOTING.md**

