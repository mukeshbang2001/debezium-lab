# ✅ Debezium Lab - Issues RESOLVED

## What Was Wrong

### 1. **Wrong Connector Classes** ❌
- **Problem**: Your `mongo-connector.json` tried to use `io.debezium.connector.mongodb.MongoDbConnector` (Debezium MongoDB Connector)
- **Available**: Only `com.mongodb.kafka.connect.MongoSourceConnector` (MongoDB Kafka Connector) was installed
- **Fix**: Changed to use the MongoDB Kafka Source Connector that was already available

### 2. **Missing Schema Configuration** ❌
- **Problem**: MongoDB Sink connector expected schema-based JSON messages but source was sending plain JSON
- **Error**: `JsonConverter with schemas.enable requires "schema" and "payload" fields`
- **Fix**: Added `"key.converter.schemas.enable": "false"` and `"value.converter.schemas.enable": "false"` to both source and sink connectors

### 3. **Topic Naming Issue** ❌
- **Problem**: Events were going to `mongo.mongo.shop.customers` instead of `mongo.shop.customers`
- **Cause**: `topic.prefix` was set to "mongo" but the connector was adding it twice
- **Fix**: Changed `topic.prefix` to `""` (empty) and used `topic.namespace.map` to control the exact topic name

### 4. **Document ID Field** ❌
- **Problem**: Sink connector was looking for field named `id` but MongoDB uses `_id`
- **Fix**: Changed `document.id.strategy.partial.value.projection.list` from `"id"` to `"_id"`

---

## Current Architecture ✅

```
MongoDB (shop.customers)
    ↓
MongoDB Source Connector (Change Streams)
    ↓
Kafka Topic: mongo.shop.customers
    ↓
MongoDB Sink Connector
    ↓
MongoDB (auditdb.audit_trail)
```

---

## Verification - Everything Works! ✅

### Test Results:

**1. INSERT Operation** ✅
```bash
# Inserted: {_id: 200, name: "Priya Sharma", age: 29, city: "Pune"}
# ✅ Appeared in Kafka topic: mongo.shop.customers
# ✅ Appeared in audit trail: auditdb.audit_trail
```

**2. UPDATE Operation** ✅
```bash
# Updated: {_id: 8} set age: 31, city: "Bangalore"
# ✅ Updated in audit trail with new values
```

**3. Connector Status** ✅
```bash
mongo-source: RUNNING ✅
mongo-sink: RUNNING ✅
```

---

## How to Test Yourself

### Quick Test Command:
```bash
# 1. Insert new data
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 999, name: "Test User", age: 25, city: "Delhi"})'

# 2. Wait 3 seconds for propagation
sleep 3

# 3. Verify in Kafka topic
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers \
  --from-beginning --max-messages 1 --timeout-ms 3000

# 4. Verify in audit trail
docker exec mongodb mongosh auditdb --eval \
  'db.audit_trail.find({_id: 999}).pretty()'
```

### All Operations Test:
```bash
# Run the operations script
docker exec mongodb mongosh /init/mongo-ops.js

# Check audit trail for all operations
docker exec mongodb mongosh auditdb --eval \
  'db.audit_trail.find().sort({_id: 1}).pretty()'
```

---

## Files Changed

1. ✅ **connectors/mongo-source.json** (NEW)
   - Uses `com.mongodb.kafka.connect.MongoSourceConnector`
   - Correct topic mapping
   - Schema disabled

2. ✅ **connectors/mongo-sink.json** (UPDATED)
   - Schema disabled for both key and value
   - Fixed document ID field from `id` to `_id`

3. ✅ **setup-connectors.sh** (NEW)
   - Automated script to register/update connectors
   - Includes status checking

4. ✅ **TROUBLESHOOTING.md** (NEW)
   - Comprehensive troubleshooting guide
   - Alternative solutions

---

## Monitoring Commands

### Check Connector Status:
```bash
curl -s http://localhost:8083/connectors/mongo-source/status | jq .
curl -s http://localhost:8083/connectors/mongo-sink/status | jq .
```

### List All Topics:
```bash
docker exec debezium-lab-kafka-1 kafka-topics \
  --bootstrap-server kafka:9092 --list
```

### Monitor Kafka Topic (Real-time):
```bash
docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers
```

### Check Audit Trail Count:
```bash
docker exec mongodb mongosh auditdb --eval \
  'db.audit_trail.countDocuments()'
```

### View All Audit Records:
```bash
docker exec mongodb mongosh auditdb --eval \
  'db.audit_trail.find().sort({_id: 1}).pretty()'
```

---

## What About Postgres Sink?

**Status**: Not implemented yet ⚠️

**Reason**: The `io.debezium.connector.jdbc.JdbcSinkConnector` plugin is not installed.

**Options**:

### Option 1: Install Debezium JDBC Connector
```bash
mkdir -p connect-plugins/debezium-jdbc
cd connect-plugins/debezium-jdbc

curl -L https://repo1.maven.org/maven2/io/debezium/debezium-connector-jdbc/2.7.0/debezium-connector-jdbc-2.7.0-plugin.tar.gz -o jdbc.tar.gz
tar -xzf jdbc.tar.gz --strip-components=1
rm jdbc.tar.gz

cd ../..
docker restart connect
sleep 10

# Register Postgres sink connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/postgres-sink-connector.json
```

### Option 2: Use Confluent JDBC Sink Connector
Download from: https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc

---

## Summary

✅ **MongoDB Source Connector**: WORKING - Captures changes from shop.customers  
✅ **Kafka Topic**: WORKING - Events flowing to mongo.shop.customers  
✅ **MongoDB Sink Connector**: WORKING - Writing to auditdb.audit_trail  
⚠️  **Postgres Sink**: NOT CONFIGURED - Plugin not installed (see options above)

---

## Current Data Flow (Working)

| Step | Component | Status |
|------|-----------|--------|
| 1 | MongoDB shop.customers (INSERT/UPDATE) | ✅ Working |
| 2 | MongoDB Source Connector | ✅ Running |
| 3 | Kafka Topic (mongo.shop.customers) | ✅ Receiving events |
| 4 | MongoDB Sink Connector | ✅ Running |
| 5 | MongoDB auditdb.audit_trail | ✅ Data persisted |

---

## Next Steps (Optional)

1. **Add Postgres Sink**: Follow Option 1 or 2 above if you need Postgres audit trail
2. **Enable Copy Existing**: Set `"copy.existing": "true"` in mongo-source.json if you want to capture existing documents
3. **Add Transforms**: Configure SMTs (Single Message Transforms) to modify data before sinking
4. **Add More Collections**: Update `collection` config to monitor other MongoDB collections

---

**All core functionality is working! 🎉**

You can now insert/update data in MongoDB shop.customers and it will automatically flow to the audit trail in auditdb.audit_trail via Kafka.

