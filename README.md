# Debezium Lab - MongoDB CDC with Audit Trail (DIFFS Capture)

## ✅ What's Working

This project captures **MongoDB change events with DIFFS** and stores them in an audit trail.

**Key Features:**
- ✅ MongoDB Change Data Capture (CDC) via Kafka
- ✅ **Audit trail captures ONLY changed fields (DIFFS)** for updates
- ✅ Full event history: INSERT, UPDATE (with diffs), DELETE
- ✅ Real-time streaming via Kafka
- ⚠️ Postgres sink not working (JDBC connector incompatible with MongoDB Change Streams)

---

## Architecture

```
MongoDB (shop.customers)
    ↓ MongoDB Change Streams
MongoDB Source Connector
    ↓ Publishes to Kafka
Kafka Topic (mongo.shop.customers)
    ↓ Consumes from Kafka
MongoDB Sink Connector
    ↓ Writes audit events
MongoDB (auditdb.changes)
    - Stores complete change events
    - updateDescription.updatedFields = ONLY DIFFS! ✨
```

---

## Quick Start (Fresh Setup)

### 1. Start Docker Containers

```bash
cd /path/to/debezium-lab
docker-compose up -d
```

**Wait ~20 seconds** for all services to be ready.

### 2. Verify Services

```bash
docker ps
```

You should see:
- `zookeeper`
- `kafka`
- `mongodb`
- `postgres`
- `connect`

### 3. Initialize MongoDB Replica Set

```bash
docker exec mongodb mongosh --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"
```

**Wait ~10 seconds** for replica set to initialize.

### 4. Setup Connectors

```bash
./setup-connectors.sh
```

This will:
- Register MongoDB Source Connector
- Register MongoDB Audit Sink Connector
- Show connector status

### 5. Verify Everything is Running

```bash
curl -s http://localhost:8083/connectors | jq .
```

Expected output:
```json
[
  "mongo-source",
  "mongo-audit-history"
]
```

---

## Running the Demo

### Option 1: Automated Test

```bash
./test-flow.sh
```

This runs a complete test:
- Inserts a test document
- Updates it
- Verifies data in Kafka and audit trail

### Option 2: Manual Test (Recommended for Demo)

#### Step 1: Insert Initial Data
```bash
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 1, name: "Mukesh", location: "Hyd", department: "Engineering"})'
```

#### Step 2: Update Some Fields
```bash
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 1}, {$set: {name: "Ritu", department: "Sales"}})'
```

#### Step 3: Update Other Fields
```bash
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 1}, {$set: {location: "Bangalore"}})'
```

#### Step 4: Check Audit Trail (SEE THE DIFFS!)
```bash
docker exec mongodb mongosh auditdb --eval '
db.changes.find({"documentKey._id": 1}).sort({clusterTime: 1}).forEach(function(doc) {
  print("\n--- " + doc.operationType.toUpperCase() + " ---");
  print("Time: " + doc.wallTime);
  
  if (doc.operationType === "insert") {
    print("Document: " + JSON.stringify(doc.fullDocument));
  } else if (doc.operationType === "update") {
    print("DIFF: " + JSON.stringify(doc.updateDescription.updatedFields));
    print("Current State: " + JSON.stringify(doc.fullDocument));
  }
});
'
```

**Expected Output:**
```
--- INSERT ---
Time: ...
Document: {"_id":1,"name":"Mukesh","location":"Hyd","department":"Engineering"}

--- UPDATE ---
Time: ...
DIFF: {"name":"Ritu","department":"Sales"}
Current State: {"_id":1,"name":"Ritu","location":"Hyd","department":"Sales"}

--- UPDATE ---
Time: ...
DIFF: {"location":"Bangalore"}
Current State: {"_id":1,"name":"Ritu","location":"Bangalore","department":"Sales"}
```

**Notice**: Each update shows ONLY the fields that changed! ✨

---

## Complete Test Script

Run this for a comprehensive demo with INSERT, UPDATE, and DELETE:

```bash
# Insert
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 100, name: "John", age: 30, city: "Mumbai", dept: "Sales"})'

sleep 3

# Update 1: Change name and age
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 100}, {$set: {name: "Johnny", age: 31}})'

sleep 3

# Update 2: Change city and dept
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 100}, {$set: {city: "Delhi", dept: "Engineering"}})'

sleep 3

# Delete
docker exec mongodb mongosh shop --eval \
  'db.customers.deleteOne({_id: 100})'

sleep 3

# View complete audit trail
docker exec mongodb mongosh auditdb --eval '
db.changes.find({"documentKey._id": 100}).sort({clusterTime: 1}).forEach(function(doc) {
  print("\n=== " + doc.operationType.toUpperCase() + " ===");
  print("Timestamp: " + doc.wallTime);
  
  if (doc.operationType === "insert") {
    print("Full Document: " + JSON.stringify(doc.fullDocument));
  } else if (doc.operationType === "update") {
    print("CHANGED FIELDS (DIFF): " + JSON.stringify(doc.updateDescription.updatedFields));
    print("Full Document After: " + JSON.stringify(doc.fullDocument));
  } else if (doc.operationType === "delete") {
    print("Deleted ID: " + JSON.stringify(doc.documentKey));
  }
});
'
```

---

## Useful Queries

### View All Audit Events
```bash
docker exec mongodb mongosh auditdb --eval 'db.changes.find().pretty()'
```

### View Only Updates (with diffs)
```bash
docker exec mongodb mongosh auditdb --eval '
db.changes.find({operationType: "update"}).forEach(function(doc) {
  print("ID: " + doc.documentKey._id);
  print("DIFF: " + JSON.stringify(doc.updateDescription.updatedFields));
  print("---");
});
'
```

### Get Audit History for Specific Document
```bash
docker exec mongodb mongosh auditdb --eval '
db.changes.find({"documentKey._id": 1}).sort({clusterTime: 1}).pretty()
'
```

### Count Events by Type
```bash
docker exec mongodb mongosh auditdb --eval '
db.changes.aggregate([
  {$group: {_id: "$operationType", count: {$sum: 1}}},
  {$sort: {count: -1}}
])
'
```

---

## Monitoring & Troubleshooting

### Check Connector Status
```bash
# List all connectors
curl -s http://localhost:8083/connectors | jq .

# Check specific connector
curl -s http://localhost:8083/connectors/mongo-source/status | jq .
curl -s http://localhost:8083/connectors/mongo-audit-history/status | jq .
```

### View Kafka Topics
```bash
docker exec debezium-lab-kafka-1 kafka-topics --bootstrap-server kafka:9092 --list
```

### Monitor Kafka Topic (Real-time)
```bash
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers
```

### View Kafka Messages from Beginning
```bash
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers \
  --from-beginning \
  --max-messages 10
```

### Check MongoDB Collections
```bash
# Source collection
docker exec mongodb mongosh shop --eval 'db.customers.find().pretty()'

# Audit collection
docker exec mongodb mongosh auditdb --eval 'db.changes.find().pretty()'
```

### View Connector Logs
```bash
docker logs connect --tail 100
```

### Restart Connectors
```bash
# Restart specific connector
curl -X POST http://localhost:8083/connectors/mongo-source/restart

# Or re-run setup script
./setup-connectors.sh
```

---

## Configuration Files

### Key Files

- **`docker-compose.yml`** - Docker services configuration
- **`connectors/mongo-source.json`** - MongoDB CDC source connector
- **`connectors/mongo-audit-history.json`** - MongoDB audit sink connector
- **`setup-connectors.sh`** - Automated connector setup script
- **`test-flow.sh`** - Automated test script

### Important Configuration

**MongoDB Source Connector** (`connectors/mongo-source.json`):
```json
{
  "publish.full.document.only": "false",  // Keep change stream metadata
  "change.stream.full.document": "updateLookup"  // Include full doc
}
```

This configuration ensures:
- `updateDescription.updatedFields` contains **ONLY changed fields** (the DIFF)
- `fullDocument` provides complete current state for context
- All change events (insert/update/delete) are captured

---

## Understanding the Audit Event Structure

### INSERT Event
```json
{
  "operationType": "insert",
  "clusterTime": Timestamp(...),
  "wallTime": ISODate("2025-11-19T21:00:00.000Z"),
  "documentKey": { "_id": 1 },
  "fullDocument": {
    "_id": 1,
    "name": "Mukesh",
    "location": "Hyd"
  },
  "ns": { "db": "shop", "coll": "customers" }
}
```

### UPDATE Event (with DIFF!)
```json
{
  "operationType": "update",
  "clusterTime": Timestamp(...),
  "wallTime": ISODate("2025-11-19T21:01:00.000Z"),
  "documentKey": { "_id": 1 },
  "updateDescription": {
    "updatedFields": { "name": "Ritu" },  // ← ONLY CHANGED FIELD!
    "removedFields": [],
    "truncatedArrays": []
  },
  "fullDocument": {
    "_id": 1,
    "name": "Ritu",
    "location": "Hyd"
  },
  "ns": { "db": "shop", "coll": "customers" }
}
```

### DELETE Event
```json
{
  "operationType": "delete",
  "clusterTime": Timestamp(...),
  "wallTime": ISODate("2025-11-19T21:02:00.000Z"),
  "documentKey": { "_id": 1 },
  "ns": { "db": "shop", "coll": "customers" }
}
```

---

## Stopping & Cleanup

### Stop All Services
```bash
docker-compose down
```

### Stop and Remove Volumes (Complete Cleanup)
```bash
docker-compose down -v
```

### Remove Only Audit Data
```bash
docker exec mongodb mongosh auditdb --eval 'db.dropDatabase()'
docker exec mongodb mongosh shop --eval 'db.customers.drop()'
```

---

## Prerequisites

- **Docker Desktop** installed (includes Docker Compose)
  - On Apple Silicon Mac, use Docker Desktop 4.x+
  - Supports both `docker compose` (new) and `docker-compose` (legacy)
- `curl` (for API calls)
- `jq` (for JSON formatting) - optional but recommended

### Install jq (if needed)
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

---

## Ports Used

- **2181** - Zookeeper
- **9092** - Kafka
- **27017** - MongoDB
- **5432** - PostgreSQL
- **8083** - Kafka Connect REST API

---

## Known Limitations

### ✅ Working
- MongoDB Change Data Capture
- Kafka streaming
- MongoDB audit trail with diffs
- INSERT, UPDATE, DELETE event capture

### ⚠️ Not Working
- **Postgres Sink**: Debezium JDBC Sink Connector is incompatible with MongoDB Change Stream format
  - MongoDB produces: `{operationType, updateDescription, fullDocument}`
  - JDBC expects: `{before, after, op}`
  - **Workaround**: Use MongoDB as audit store (recommended) or write custom consumer

---

## Performance Tips

### Create Indexes on Audit Collection
```bash
docker exec mongodb mongosh auditdb --eval '
// Index for document lookups
db.changes.createIndex({"documentKey._id": 1, "clusterTime": 1});

// Index for operation type queries
db.changes.createIndex({"operationType": 1, "wallTime": -1});

// TTL index to auto-delete old audits (90 days)
db.changes.createIndex({"wallTime": 1}, {expireAfterSeconds: 7776000});
'
```

---

## Troubleshooting

See `TROUBLESHOOTING.md` for detailed troubleshooting guide.

### Quick Fixes

**Connector Failed:**
```bash
./setup-connectors.sh
```

**MongoDB Replica Set Not Initialized:**
```bash
docker exec mongodb mongosh --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"
```

**Kafka Connect Not Ready:**
```bash
docker restart connect
sleep 15
./setup-connectors.sh
```

---

## Additional Resources

- **MongoDB Change Streams**: https://www.mongodb.com/docs/manual/changeStreams/
- **MongoDB Kafka Connector**: https://www.mongodb.com/docs/kafka-connector/current/
- **Kafka Connect**: https://docs.confluent.io/platform/current/connect/index.html

---

## Summary

✅ **What You Have:**
- Real-time MongoDB CDC
- Kafka-based event streaming
- **Audit trail that captures ONLY changed fields (diffs)**
- Complete event history (INSERT, UPDATE with diffs, DELETE)

✅ **Quick Demo:**
```bash
# Start everything
docker-compose up -d
sleep 20
docker exec mongodb mongosh --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"
sleep 10
./setup-connectors.sh

# Run test
./test-flow.sh

# Or manual test
docker exec mongodb mongosh shop --eval 'db.customers.insertOne({_id: 1, name: "Mukesh", city: "Hyd"})'
sleep 3
docker exec mongodb mongosh shop --eval 'db.customers.updateOne({_id: 1}, {$set: {name: "Ritu"}})'
sleep 3
docker exec mongodb mongosh auditdb --eval 'db.changes.find({"documentKey._id": 1}).pretty()'
```

**The audit trail will show: DIFF = `{"name": "Ritu"}`** ✨

---

**For detailed setup and troubleshooting, see `TROUBLESHOOTING.md`**
