# Debezium Lab - Troubleshooting Guide

## Table of Contents
1. [What's Working](#whats-working)
2. [Common Issues](#common-issues)
3. [Setup from Scratch](#setup-from-scratch)
4. [Connector Issues](#connector-issues)
5. [MongoDB Issues](#mongodb-issues)
6. [Kafka Issues](#kafka-issues)
7. [Postgres Limitations](#postgres-limitations)
8. [Verification Commands](#verification-commands)

---

## What's Working

### ✅ MongoDB CDC with Audit Trail (DIFFS Capture)

**Current Setup:**
- MongoDB Source Connector: Captures change events from `shop.customers`
- Kafka Topic: `mongo.shop.customers`
- MongoDB Sink Connector: Writes to `auditdb.changes`
- **Audit trail captures ONLY changed fields (DIFFS)** for UPDATE operations

**Test Result:**
```javascript
// INSERT
{operationType: "insert", fullDocument: {_id: 1, name: "Mukesh", city: "Hyd"}}

// UPDATE - ONLY DIFF!
{operationType: "update", updateDescription: {updatedFields: {name: "Ritu"}}}
```

### ⚠️ What's NOT Working

**Postgres Sink:**
- Debezium JDBC Sink Connector is incompatible with MongoDB Change Streams
- MongoDB produces: `{operationType, updateDescription, fullDocument}`
- JDBC expects: `{before, after, op}`
- **Solution**: Use MongoDB as audit store or write custom consumer

---

## Common Issues

### Issue 1: "Connector mongo-source not found"

**Symptoms:**
```bash
curl -s http://localhost:8083/connectors/mongo-source/status
# Returns 404
```

**Solution:**
```bash
./setup-connectors.sh
```

**Or manually:**
```bash
cd /path/to/debezium-lab
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/mongo-source.json
```

---

### Issue 2: "MongoDB Replica Set Not Initialized"

**Symptoms:**
- Source connector shows FAILED
- Error: "MongoCommandException: not master and slaveOk=false"

**Check:**
```bash
docker exec mongodb mongosh --eval "rs.status()"
```

**Solution:**
```bash
docker exec mongodb mongosh --eval \
  "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"

# Wait 10 seconds
sleep 10

# Verify
docker exec mongodb mongosh --eval "rs.status()" | grep "stateStr"
```

Should show: `"stateStr": "PRIMARY"`

---

### Issue 3: "Kafka Connect Not Ready"

**Symptoms:**
```bash
curl http://localhost:8083/
# Connection refused or timeout
```

**Solution:**
```bash
# Check if container is running
docker ps | grep connect

# Restart if needed
docker restart connect

# Wait for it to be ready
sleep 15

# Verify
curl -s http://localhost:8083/ | jq .
```

---

### Issue 4: "No Events in Kafka Topic"

**Symptoms:**
- Connector shows RUNNING
- But no messages in Kafka

**Diagnosis:**
```bash
# Check connector status
curl -s http://localhost:8083/connectors/mongo-source/status | jq .

# Check if topic exists
docker exec debezium-lab-kafka-1 kafka-topics \
  --bootstrap-server kafka:9092 --list | grep mongo

# Try to consume
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers \
  --from-beginning \
  --timeout-ms 5000
```

**Solutions:**

1. **Restart connector:**
```bash
curl -X POST http://localhost:8083/connectors/mongo-source/restart
sleep 5
```

2. **Check MongoDB replica set:**
```bash
docker exec mongodb mongosh --eval "rs.status()"
```

3. **Insert test data:**
```bash
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 999, name: "Test", test: true})'
```

---

### Issue 5: "Audit Trail Empty"

**Symptoms:**
```bash
docker exec mongodb mongosh auditdb --eval 'db.changes.find().count()'
# Returns 0
```

**Diagnosis Steps:**

1. **Check sink connector:**
```bash
curl -s http://localhost:8083/connectors/mongo-audit-history/status | jq .
```

2. **Check if messages in Kafka:**
```bash
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 5000
```

3. **Check sink connector logs:**
```bash
docker logs connect 2>&1 | grep -i "mongo-audit-history" | tail -20
```

**Solution:**
```bash
# Restart sink connector
curl -X POST http://localhost:8083/connectors/mongo-audit-history/restart

# Or recreate all connectors
./setup-connectors.sh
```

---

### Issue 6: "Connector Shows FAILED"

**Get Error Details:**
```bash
curl -s http://localhost:8083/connectors/mongo-source/status | \
  jq '.tasks[0].trace' -r
```

**Common Errors:**

#### Error: "Failed to find any class that implements Connector"
**Solution:** Plugin not installed or not in correct directory
```bash
ls -la /Users/mukesh.bang/projects/debezium-lab/connect-plugins/
# Should see mongo-kafka/ directory

# Restart Connect to reload plugins
docker restart connect
sleep 15
```

#### Error: "JsonConverter with schemas.enable requires schema"
**Solution:** Schema configuration mismatch
```bash
# Verify connector config has:
"key.converter.schemas.enable": "false",
"value.converter.schemas.enable": "false"
```

#### Error: "MongoCommandException: not master"
**Solution:** Replica set not initialized (see Issue 2)

---

## Setup from Scratch

### Complete Fresh Setup on New Machine

#### 1. Prerequisites

```bash
# Check Docker
docker --version
docker-compose --version

# Check curl
curl --version

# Install jq (optional but recommended)
# macOS:
brew install jq
# Ubuntu:
sudo apt-get install jq
```

#### 2. Clone/Copy Project

```bash
# Copy project to target machine
scp -r debezium-lab user@target-machine:/path/to/

# Or extract from archive
tar -xzf debezium-lab.tar.gz
cd debezium-lab
```

#### 3. Start Services

```bash
# Start all containers
docker-compose up -d

# Wait for services to start
sleep 20

# Verify all containers are running
docker ps
```

Expected containers:
- `debezium-lab-zookeeper-1`
- `debezium-lab-kafka-1`
- `mongodb`
- `debezium-lab-postgres-1`
- `connect`

#### 4. Initialize MongoDB Replica Set

```bash
# Initialize replica set (REQUIRED for change streams)
docker exec mongodb mongosh --eval \
  "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"

# Wait for initialization
sleep 10

# Verify
docker exec mongodb mongosh --eval "rs.status().members[0].stateStr"
# Should output: PRIMARY
```

#### 5. Setup Connectors

```bash
# Wait for Kafka Connect to be ready
until curl -s http://localhost:8083/ > /dev/null; do
  echo "Waiting for Kafka Connect..."
  sleep 2
done

# Register connectors
./setup-connectors.sh
```

Expected output:
```
✓ MongoDB Source Connector registered successfully
✓ MongoDB Sink Connector registered successfully

MongoDB Source: RUNNING
MongoDB Sink: RUNNING
```

#### 6. Run Test

```bash
./test-flow.sh
```

Or manual test:
```bash
# Insert
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 1, name: "Mukesh", city: "Hyd"})'

# Update
sleep 3
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 1}, {$set: {name: "Ritu"}})'

# Check audit trail
sleep 3
docker exec mongodb mongosh auditdb --eval \
  'db.changes.find({"documentKey._id": 1}).pretty()'
```

**Expected Result:** Audit trail shows DIFF = `{"name": "Ritu"}`

---

## Connector Issues

### List All Connectors
```bash
curl -s http://localhost:8083/connectors | jq .
```

### Get Connector Config
```bash
curl -s http://localhost:8083/connectors/mongo-source | jq .config
```

### Get Connector Status
```bash
curl -s http://localhost:8083/connectors/mongo-source/status | jq .
```

### Restart Connector
```bash
curl -X POST http://localhost:8083/connectors/mongo-source/restart
```

### Delete Connector
```bash
curl -X DELETE http://localhost:8083/connectors/mongo-source
```

### Update Connector Config
```bash
curl -X PUT http://localhost:8083/connectors/mongo-source/config \
  -H "Content-Type: application/json" \
  -d @connectors/mongo-source.json
```

### View Available Connector Plugins
```bash
curl -s http://localhost:8083/connector-plugins | jq '.[] | {class, type, version}'
```

---

## MongoDB Issues

### Check Connection
```bash
docker exec mongodb mongosh --eval "db.version()"
```

### Check Replica Set Status
```bash
docker exec mongodb mongosh --eval "rs.status()" | grep -A 5 stateStr
```

### View Collections
```bash
# Source database
docker exec mongodb mongosh shop --eval "show collections"

# Audit database
docker exec mongodb mongosh auditdb --eval "show collections"
```

### Check Collection Counts
```bash
docker exec mongodb mongosh shop --eval "db.customers.countDocuments()"
docker exec mongodb mongosh auditdb --eval "db.changes.countDocuments()"
```

### View Change Events
```bash
docker exec mongodb mongosh auditdb --eval '
db.changes.find().limit(5).forEach(function(doc) {
  print(JSON.stringify(doc, null, 2));
});
'
```

### Drop Collections (Clean Slate)
```bash
docker exec mongodb mongosh shop --eval "db.customers.drop()"
docker exec mongodb mongosh auditdb --eval "db.changes.drop()"
```

---

## Kafka Issues

### List Topics
```bash
docker exec debezium-lab-kafka-1 kafka-topics \
  --bootstrap-server kafka:9092 --list
```

### Describe Topic
```bash
docker exec debezium-lab-kafka-1 kafka-topics \
  --bootstrap-server kafka:9092 \
  --describe \
  --topic mongo.shop.customers
```

### Consume Messages
```bash
# From beginning
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers \
  --from-beginning \
  --max-messages 10

# Real-time monitoring
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers
```

### Delete Topic
```bash
docker exec debezium-lab-kafka-1 kafka-topics \
  --bootstrap-server kafka:9092 \
  --delete \
  --topic mongo.shop.customers
```

### List Consumer Groups
```bash
docker exec debezium-lab-kafka-1 kafka-consumer-groups \
  --bootstrap-server kafka:9092 --list
```

### Reset Consumer Group Offset
```bash
docker exec debezium-lab-kafka-1 kafka-consumer-groups \
  --bootstrap-server kafka:9092 \
  --group connect-mongo-audit-history \
  --reset-offsets \
  --to-earliest \
  --topic mongo.shop.customers \
  --execute
```

---

## Postgres Limitations

### Why Postgres Sink Doesn't Work

**Technical Reason:**
- **Debezium JDBC Sink** expects Debezium envelope format:
  ```json
  {
    "before": {...},
    "after": {...},
    "source": {...},
    "op": "u"
  }
  ```

- **MongoDB Change Streams** produce:
  ```json
  {
    "operationType": "update",
    "updateDescription": {
      "updatedFields": {...}
    },
    "fullDocument": {...},
    "documentKey": {...}
  }
  ```

These formats are incompatible!

### Workarounds

#### Option 1: Use MongoDB as Audit Store (Recommended ✅)
MongoDB is actually ideal for audit trails:
- Native support for nested JSON
- Change streams designed for this use case
- No schema migration issues
- Better query performance for event data

#### Option 2: Custom Consumer
Write a simple consumer:
```python
from kafka import KafkaConsumer
import psycopg2
import json

consumer = KafkaConsumer('mongo.shop.customers')
conn = psycopg2.connect(...)

for message in consumer:
    event = json.loads(message.value)
    
    # Extract diff
    if event.get('operationType') == 'update':
        diff = event['updateDescription']['updatedFields']
        doc_id = event['documentKey']['_id']
        
        # Insert to Postgres
        cursor.execute(
            "INSERT INTO audit_events (doc_id, diff, timestamp) VALUES (%s, %s, %s)",
            (doc_id, json.dumps(diff), event['wallTime'])
        )
```

#### Option 3: Confluent JDBC Sink
May have better schemaless support:
- Download: https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc
- Try instead of Debezium JDBC Sink

---

## Verification Commands

### Full System Health Check

```bash
echo "=== Services ==="
docker ps --format "table {{.Names}}\t{{.Status}}"

echo -e "\n=== Kafka Connect ==="
curl -s http://localhost:8083/ | jq '{version, commit}'

echo -e "\n=== Connectors ==="
curl -s http://localhost:8083/connectors | jq .

echo -e "\n=== Connector Status ==="
for connector in mongo-source mongo-audit-history; do
  echo "$connector:"
  curl -s http://localhost:8083/connectors/$connector/status | \
    jq '{connector: .connector.state, task: .tasks[0].state}'
done

echo -e "\n=== MongoDB Replica Set ==="
docker exec mongodb mongosh --eval "rs.status().members[0].stateStr"

echo -e "\n=== Data Counts ==="
echo -n "Source documents: "
docker exec mongodb mongosh shop --quiet --eval "db.customers.countDocuments()"
echo -n "Audit events: "
docker exec mongodb mongosh auditdb --quiet --eval "db.changes.countDocuments()"

echo -e "\n=== Kafka Topics ==="
docker exec debezium-lab-kafka-1 kafka-topics \
  --bootstrap-server kafka:9092 --list | grep mongo
```

### Quick Test Script

```bash
#!/bin/bash

echo "Running quick test..."

# Insert
docker exec mongodb mongosh shop --quiet --eval \
  'db.customers.insertOne({_id: 99, name: "Test", status: "active"})'

sleep 3

# Update
docker exec mongodb mongosh shop --quiet --eval \
  'db.customers.updateOne({_id: 99}, {$set: {status: "inactive"}})'

sleep 3

# Check audit
echo -e "\n=== Audit Trail (should show DIFF) ==="
docker exec mongodb mongosh auditdb --quiet --eval '
db.changes.find({"documentKey._id": 99, operationType: "update"}).forEach(function(doc) {
  print("DIFF: " + JSON.stringify(doc.updateDescription.updatedFields));
});
'

# Cleanup
docker exec mongodb mongosh shop --quiet --eval 'db.customers.deleteOne({_id: 99})'
```

---

## Logs & Debugging

### View Connector Logs
```bash
docker logs connect --tail 100
```

### Follow Logs in Real-time
```bash
docker logs -f connect
```

### Search for Errors
```bash
docker logs connect 2>&1 | grep -i error | tail -20
```

### View Specific Connector Logs
```bash
docker logs connect 2>&1 | grep -i "mongo-source" | tail -20
```

---

## Performance Optimization

### Create Indexes on Audit Collection

```bash
docker exec mongodb mongosh auditdb --eval '
// Index for document lookups
db.changes.createIndex({"documentKey._id": 1, "clusterTime": 1});

// Index for operation type queries
db.changes.createIndex({"operationType": 1, "wallTime": -1});

// Index for timestamp queries
db.changes.createIndex({"wallTime": -1});
'
```

### Add TTL Index (Auto-delete old audits)

```bash
docker exec mongodb mongosh auditdb --eval '
// Delete audits older than 90 days
db.changes.createIndex(
  {"wallTime": 1},
  {expireAfterSeconds: 7776000}
);
'
```

---

## Reset Everything

### Soft Reset (Keep Docker Images)
```bash
# Stop and remove containers
docker-compose down

# Remove volumes
docker volume prune -f

# Start fresh
docker-compose up -d
sleep 20

# Initialize MongoDB
docker exec mongodb mongosh --eval \
  "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"
sleep 10

# Setup connectors
./setup-connectors.sh
```

### Hard Reset (Remove Everything)
```bash
docker-compose down -v
docker system prune -a -f
docker-compose up -d
# Then follow fresh setup steps
```

---

## FAQ

**Q: Why do I need a MongoDB replica set for CDC?**
A: MongoDB change streams only work on replica sets. Even for single-node setups, you need to initialize a replica set.

**Q: Can I capture existing documents?**
A: Set `"copy.existing": "true"` in `mongo-source.json`. But this creates snapshots, not change events.

**Q: How do I see what changed in an update?**
A: Check `updateDescription.updatedFields` in the audit event. This contains ONLY the changed fields.

**Q: Why is Postgres empty?**
A: JDBC Sink is incompatible with MongoDB Change Stream format. Use MongoDB as audit store or write custom consumer.

**Q: Can I add more source collections?**
A: Yes! Update `mongo-source.json`:
```json
"database": "shop",
"collection": "",  // Empty = all collections
// Or specify multiple collections
```

**Q: How do I query audit history for a specific document?**
```bash
docker exec mongodb mongosh auditdb --eval '
db.changes.find({"documentKey._id": YOUR_ID}).sort({clusterTime: 1}).pretty()
'
```

---

## Summary Checklist

Setup checklist for new environment:

- [ ] Docker & Docker Compose installed
- [ ] Run `docker-compose up -d`
- [ ] Wait 20 seconds
- [ ] Initialize MongoDB replica set
- [ ] Wait 10 seconds  
- [ ] Run `./setup-connectors.sh`
- [ ] Run `./test-flow.sh` to verify
- [ ] Check audit trail shows diffs

Troubleshooting checklist:

- [ ] All 5 containers running (`docker ps`)
- [ ] MongoDB replica set initialized (`rs.status()`)
- [ ] Kafka Connect healthy (`curl localhost:8083`)
- [ ] Both connectors RUNNING
- [ ] Kafka topic exists
- [ ] Test data inserted
- [ ] Audit events appearing

---

**For more details, see README.md**
