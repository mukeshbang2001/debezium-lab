# Debezium Lab - Project Summary

## ✅ What This Project Does

Captures MongoDB change events (CDC) with **DIFFS** and stores them in an audit trail.

**Key Achievement:** When you update a document, the audit trail captures **ONLY the changed fields**, not the entire document!

---

## 📁 Project Structure

```
debezium-lab/
├── docker-compose.yml              # Docker services configuration
├── fresh-setup.sh                  # Complete setup script for fresh environments ⭐
├── setup-connectors.sh             # Register Kafka connectors
├── test-flow.sh                    # Automated test script
├── README.md                       # Complete documentation ⭐
├── QUICKSTART.md                   # 5-minute quick start guide ⭐
├── TROUBLESHOOTING.md              # Troubleshooting guide ⭐
├── WORKING-SOLUTION.md             # Technical details about the solution
├── FIXED-SUMMARY.md                # What was fixed during development
├── PROJECT_SUMMARY.md              # This file
├── connectors/
│   ├── mongo-source.json           # MongoDB CDC source connector config
│   ├── mongo-audit-history.json    # MongoDB audit sink connector config
│   ├── mongo-sink.json             # Alternative sink config
│   ├── postgres-audit-sink.json    # Postgres sink (not working)
│   └── postgres-sink-connector.json
├── connect-plugins/
│   ├── mongo-kafka/                # MongoDB Kafka connector plugin
│   └── debezium-jdbc/              # Debezium JDBC connector plugin
└── init/
    ├── init-mongo.js               # MongoDB initialization script
    ├── init-postgres.sql           # Postgres initialization script
    ├── mongo-ops.js                # Sample MongoDB operations
    └── run-mongo-ops.sh            # Run MongoDB operations
```

---

## 🚀 Quick Start (3 Commands)

```bash
# 1. Setup everything
./fresh-setup.sh

# 2. Run test
./test-flow.sh

# 3. View audit trail
docker exec mongodb mongosh auditdb --eval 'db.changes.find().pretty()'
```

---

## 📚 Documentation Files

### Start Here
- **QUICKSTART.md** - Get running in 5 minutes
- **README.md** - Complete guide with all commands

### When You Need Help
- **TROUBLESHOOTING.md** - Solutions to common issues
- **WORKING-SOLUTION.md** - How the diff capture works

### Reference
- **FIXED-SUMMARY.md** - What issues were resolved
- **PROJECT_SUMMARY.md** - This overview

---

## 🔧 Scripts

### fresh-setup.sh ⭐
Complete automated setup for fresh environments.
- Starts Docker containers
- Initializes MongoDB replica set
- Registers connectors
- Runs test
- Shows results

**Usage:**
```bash
./fresh-setup.sh
```

### setup-connectors.sh
Registers Kafka Connect connectors.
- Removes old connectors
- Registers MongoDB source
- Registers MongoDB sink
- Shows status

**Usage:**
```bash
./setup-connectors.sh
```

### test-flow.sh
Automated test script.
- Inserts test document
- Performs multiple updates
- Shows audit trail with diffs
- Cleans up

**Usage:**
```bash
./test-flow.sh
```

---

## 📋 Connector Configurations

### mongo-source.json
MongoDB CDC Source Connector
- Reads from: `shop.customers`
- Publishes to: Kafka topic `mongo.shop.customers`
- **Key config**: `"publish.full.document.only": "false"` enables diff capture

### mongo-audit-history.json
MongoDB Sink Connector
- Reads from: Kafka topic `mongo.shop.customers`
- Writes to: `auditdb.changes`
- Stores complete change events with diffs

---

## 🐳 Docker Services

| Service | Port | Description |
|---------|------|-------------|
| zookeeper | 2181 | Kafka coordination |
| kafka | 9092 | Message broker |
| mongodb | 27017 | Source & audit database |
| postgres | 5432 | (Not used - JDBC sink incompatible) |
| connect | 8083 | Kafka Connect REST API |

---

## 🗄️ Database Schema

### Source Database: `shop.customers`
MongoDB collection where changes are captured from.

**Example:**
```json
{ "_id": 1, "name": "Mukesh", "city": "Hyd", "dept": "Engineering" }
```

### Audit Database: `auditdb.changes`
MongoDB collection storing change events.

**INSERT Event:**
```json
{
  "operationType": "insert",
  "fullDocument": { "_id": 1, "name": "Mukesh", "city": "Hyd" },
  "documentKey": { "_id": 1 }
}
```

**UPDATE Event (with DIFF!):**
```json
{
  "operationType": "update",
  "documentKey": { "_id": 1 },
  "updateDescription": {
    "updatedFields": { "name": "Ritu" },  // ← ONLY CHANGED FIELD!
    "removedFields": [],
    "truncatedArrays": []
  },
  "fullDocument": { "_id": 1, "name": "Ritu", "city": "Hyd" }
}
```

---

## ✅ What's Working

- ✅ MongoDB Change Data Capture (CDC)
- ✅ Real-time Kafka streaming
- ✅ **Audit trail with DIFF capture**
- ✅ INSERT events (full document)
- ✅ UPDATE events (only changed fields)
- ✅ DELETE events (document ID)
- ✅ Automated setup scripts
- ✅ Test scripts

---

## ⚠️ Known Limitations

### Postgres Sink Not Working
**Reason:** Debezium JDBC Sink requires Debezium envelope format, but MongoDB Change Streams produce different format.

**Workarounds:**
1. Use MongoDB as audit store (recommended - already working!)
2. Write custom consumer
3. Try Confluent JDBC Sink

**Details:** See TROUBLESHOOTING.md → "Postgres Limitations"

---

## 🎯 Use Cases

This setup is perfect for:
- Audit logging (track who changed what)
- Event sourcing
- Data replication with change tracking
- Compliance requirements
- Debugging data changes
- Real-time analytics on changes

---

## 📊 Sample Queries

### Get all changes for a document
```javascript
db.changes.find({"documentKey._id": 1}).sort({clusterTime: 1})
```

### Get only UPDATE operations with diffs
```javascript
db.changes.find({operationType: "update"}).forEach(function(doc) {
  print("ID: " + doc.documentKey._id);
  print("DIFF: " + JSON.stringify(doc.updateDescription.updatedFields));
});
```

### Count events by type
```javascript
db.changes.aggregate([
  {$group: {_id: "$operationType", count: {$sum: 1}}},
  {$sort: {count: -1}}
])
```

---

## 🔍 Verification Commands

### Check all systems
```bash
# Services running
docker ps

# Kafka Connect ready
curl -s http://localhost:8083/ | jq .

# Connectors registered
curl -s http://localhost:8083/connectors | jq .

# Connectors status
curl -s http://localhost:8083/connectors/mongo-source/status | jq .

# MongoDB replica set
docker exec mongodb mongosh --eval "rs.status().members[0].stateStr"

# Source collection count
docker exec mongodb mongosh shop --eval "db.customers.countDocuments()"

# Audit collection count
docker exec mongodb mongosh auditdb --eval "db.changes.countDocuments()"
```

---

## 🛠️ Common Tasks

### Add new source collection
Edit `connectors/mongo-source.json`:
```json
"database": "shop",
"collection": ""  // Empty = all collections
```

### Change Kafka topic name
Edit `connectors/mongo-source.json`:
```json
"topic.namespace.map": "{\"shop.customers\": \"your-topic-name\"}"
```

### Auto-delete old audits (TTL)
```javascript
db.changes.createIndex(
  {"wallTime": 1},
  {expireAfterSeconds: 7776000}  // 90 days
)
```

### Create indexes for performance
```javascript
db.changes.createIndex({"documentKey._id": 1, "clusterTime": 1})
db.changes.createIndex({"operationType": 1, "wallTime": -1})
```

---

## 🚨 Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| Connector not found | Run `./setup-connectors.sh` |
| MongoDB not PRIMARY | Run replica set init script |
| Kafka Connect down | `docker restart connect && sleep 15` |
| No events in audit | Check connector status & Kafka topic |
| Empty Kafka topic | Insert test data in MongoDB |

**Full guide:** See TROUBLESHOOTING.md

---

## 📈 Performance Tips

1. Create indexes on audit collection
2. Use TTL index for auto-cleanup
3. Partition Kafka topic for high throughput
4. Monitor connector lag
5. Tune batch sizes

---

## 🔗 Resources

- MongoDB Change Streams: https://www.mongodb.com/docs/manual/changeStreams/
- MongoDB Kafka Connector: https://www.mongodb.com/docs/kafka-connector/
- Kafka Connect: https://docs.confluent.io/platform/current/connect/
- Debezium: https://debezium.io/

---

## 📝 License & Credits

This is a demonstration/lab project for learning MongoDB CDC with Kafka.

---

## 💡 Key Takeaway

**The audit trail captures ONLY the changed fields (diffs) for UPDATE operations!**

Example:
- Original: `{name: "Mukesh", city: "Hyd"}`
- Update: Change name to "Ritu"
- **Audit shows:** `{"name": "Ritu"}` ← Only the diff!

This is exactly what you wanted! ✨

---

**For detailed instructions, start with QUICKSTART.md or README.md**
