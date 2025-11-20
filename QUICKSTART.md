# Quick Start Guide

Get up and running in **5 minutes**!

## Prerequisites

- Docker & Docker Compose installed
- `curl` installed
- `jq` installed (optional but recommended)

## Setup on Fresh Machine

### 1. Start Everything

```bash
cd /path/to/debezium-lab
./fresh-setup.sh
```

This script will:
- Start all Docker containers
- Initialize MongoDB replica set
- Register connectors
- Run a test

**Expected output:** `✅ All systems operational!`

---

### 2. Run Test (Manual)

```bash
# Insert document
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 1, name: "Mukesh", city: "Hyd"})'

# Update document
sleep 3
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 1}, {$set: {name: "Ritu"}})'

# View audit trail (see the DIFF!)
sleep 3
docker exec mongodb mongosh auditdb --eval \
  'db.changes.find({"documentKey._id": 1}).pretty()'
```

**Expected:** Audit shows DIFF = `{"name": "Ritu"}`

---

### 3. Run Automated Test

```bash
./test-flow.sh
```

This runs a complete test with INSERT, UPDATE (multiple), and DELETE operations.

---

## What You Get

✅ **MongoDB CDC** - Captures all changes from `shop.customers`  
✅ **Kafka Streaming** - Events flow through Kafka topic  
✅ **Audit Trail with DIFFS** - Only changed fields captured in updates  
✅ **Complete History** - INSERT, UPDATE (diffs), DELETE events  

---

## Quick Commands

### View Audit Trail
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

### Check Connector Status
```bash
curl -s http://localhost:8083/connectors | jq .
```

### Monitor Kafka Topic
```bash
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers
```

---

## Troubleshooting

### Connectors Not Running?
```bash
./setup-connectors.sh
```

### MongoDB Replica Set Issue?
```bash
docker exec mongodb mongosh --eval \
  "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})"
sleep 10
./setup-connectors.sh
```

### Start Fresh?
```bash
docker-compose down -v
./fresh-setup.sh
```

---

## Demo Script

Copy-paste this for a complete demo:

```bash
# Insert
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 100, name: "John", age: 30, city: "Mumbai"})'

sleep 3

# Update 1
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 100}, {$set: {name: "Johnny", age: 31}})'

sleep 3

# Update 2  
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 100}, {$set: {city: "Delhi"}})'

sleep 3

# View audit trail
docker exec mongodb mongosh auditdb --eval '
db.changes.find({"documentKey._id": 100}).sort({clusterTime: 1}).forEach(function(doc) {
  print("\n" + doc.operationType.toUpperCase());
  if (doc.operationType === "update") {
    print("DIFF: " + JSON.stringify(doc.updateDescription.updatedFields));
  }
});
'

# Cleanup
docker exec mongodb mongosh shop --eval 'db.customers.deleteOne({_id: 100})'
```

**Output shows:**
- INSERT: Full document
- UPDATE 1: DIFF = `{"name":"Johnny","age":31}`
- UPDATE 2: DIFF = `{"city":"Delhi"}`

---

## Next Steps

- See **README.md** for complete documentation
- See **TROUBLESHOOTING.md** for troubleshooting guide
- See **WORKING-SOLUTION.md** for technical details

---

## Architecture

```
MongoDB (shop.customers)
    ↓
MongoDB Source Connector
    ↓
Kafka (mongo.shop.customers)
    ↓
MongoDB Audit Sink
    ↓
MongoDB (auditdb.changes)
    - updateDescription.updatedFields = DIFFS! ✨
```

---

That's it! Your audit trail with diffs is operational! 🎉

