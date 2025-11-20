# ✅ Working Solution - MongoDB Audit Trail with DIFFS

## **What's Working** 🎉

Your system is now capturing **ONLY the changed fields** (diffs) in the audit trail!

### **Test Results:**

**Source Collection** (`shop.customers`):
```javascript
{ _id: 1, name: 'Ritu', location: 'Hyd' }
```

**Audit Trail** (`auditdb.changes`) - **WITH DIFFS**:
```javascript
// INSERT EVENT - Full document
{
  operationType: 'insert',
  documentKey: { _id: 1 },
  fullDocument: { _id: 1, name: 'Mukesh', location: 'Hyd' }
}

// UPDATE EVENT - ONLY CHANGED FIELDS! ✨
{
  operationType: 'update',
  documentKey: { _id: 1 },
  updateDescription: {
    updatedFields: { name: 'Ritu' },  // <-- DIFF ONLY!
    removedFields: [],
    truncatedArrays: []
  },
  fullDocument: { _id: 1, name: 'Ritu', location: 'Hyd' }
}
```

**The `updateDescription.updatedFields` contains ONLY the diff!** ✅

---

## **Architecture**

```
MongoDB (shop.customers)
    ↓ 
MongoDB Source Connector
  (publish.full.document.only = false)
  (change.stream.full.document = updateLookup)
    ↓
Kafka Topic (mongo.shop.customers)
  - INSERT events: full document
  - UPDATE events: full document + updateDescription (diff)
  - DELETE events: documentKey only
    ↓
MongoDB Sink Connector
    ↓
MongoDB (auditdb.changes)
  - Stores complete change stream events
  - updateDescription.updatedFields = DIFF
```

---

## **Key Configuration**

### **Source Connector** (`mongo-source.json`):
```json
{
  "publish.full.document.only": "false",  // Keep change stream metadata
  "change.stream.full.document": "updateLookup"  // Include full doc for updates
}
```

This gives you:
- `operationType`: "insert", "update", "delete", "replace"
- `documentKey`: The `_id` of the changed document
- `updateDescription`: **THE DIFF** - only changed fields
- `fullDocument`: The complete current state (for context)

---

## **How to Query the Audit Trail**

### **Get all changes for a specific document:**
```javascript
db.changes.find({ "documentKey._id": 1 }).pretty()
```

### **Get only UPDATE operations:**
```javascript
db.changes.find({ operationType: "update" }).pretty()
```

### **Get only the DIFFS (changed fields):**
```javascript
db.changes.find({ operationType: "update" }).forEach(function(doc) {
  print("ID: " + doc.documentKey._id);
  print("Changed fields: " + JSON.stringify(doc.updateDescription.updatedFields));
  print("---");
});
```

### **Get audit history for ID=1:**
```javascript
db.changes.find({ "documentKey._id": 1 }).sort({ "clusterTime": 1 }).forEach(function(doc) {
  print(doc.operationType.toUpperCase() + " at " + doc.wallTime);
  if (doc.updateDescription) {
    print("  Changed: " + JSON.stringify(doc.updateDescription.updatedFields));
  } else if (doc.fullDocument) {
    print("  Document: " + JSON.stringify(doc.fullDocument));
  }
  print("");
});
```

---

## **About Postgres Sink**

### **Current Status:** ⚠️ Not Working

**Reason**: Debezium JDBC Sink Connector requires **schema-based** messages, but MongoDB Change Streams produce **schemaless JSON**.

### **Workaround Options:**

#### **Option 1: Store as JSONB in Postgres** (Manual approach)
Create a table:
```sql
CREATE TABLE audit_events (
    id SERIAL PRIMARY KEY,
    event_data JSONB NOT NULL,
    operation_type VARCHAR(20),
    document_id INTEGER,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

Then use a custom consumer to read from Kafka and write to Postgres.

#### **Option 2: Use Confluent JDBC Sink Connector**
The Confluent JDBC sink has better support for schemaless data.

Download from: https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc

#### **Option 3: Keep MongoDB as Audit Store** ✅ RECOMMENDED
MongoDB is actually **perfect** for audit trails because:
- Native support for complex nested structures
- Change streams are designed for this
- JSONB-like querying capabilities
- No schema migration headaches
- Better performance for event sourcing

---

## **Testing the System**

### **Insert Test:**
```bash
docker exec mongodb mongosh shop --eval \
  'db.customers.insertOne({_id: 10, name: "Alice", age: 30, city: "Mumbai"})'

sleep 3

docker exec mongodb mongosh auditdb --eval \
  'db.changes.find({"documentKey._id": 10}).pretty()'
```

### **Update Test (to see DIFF):**
```bash
# Update name and city
docker exec mongodb mongosh shop --eval \
  'db.customers.updateOne({_id: 10}, {$set: {name: "Alicia", city: "Delhi"}})'

sleep 3

# Check audit - will show ONLY changed fields
docker exec mongodb mongosh auditdb --eval \
  'db.changes.find({"documentKey._id": 10, operationType: "update"}).forEach(function(doc) {
    print("Changed fields: " + JSON.stringify(doc.updateDescription.updatedFields));
  })'
```

**Expected output:**
```
Changed fields: {"name":"Alicia","city":"Delhi"}
```

### **Delete Test:**
```bash
docker exec mongodb mongosh shop --eval \
  'db.customers.deleteOne({_id: 10})'

sleep 3

docker exec mongodb mongosh auditdb --eval \
  'db.changes.find({"documentKey._id": 10, operationType: "delete"}).pretty()'
```

---

## **Connector Status**

Check all connectors:
```bash
curl -s http://localhost:8083/connectors | jq .
```

Check status:
```bash
curl -s http://localhost:8083/connectors/mongo-source/status | \
  jq '{name, connector: .connector.state, task: .tasks[0].state}'

curl -s http://localhost:8083/connectors/mongo-audit-history/status | \
  jq '{name, connector: .connector.state, task: .tasks[0].state}'
```

---

## **What Each Field Means**

### **Change Event Structure:**

```javascript
{
  _id: { ... },  // Resume token (for reconnection)
  
  operationType: "update",  // insert, update, delete, replace
  
  clusterTime: Timestamp(...),  // When it happened in MongoDB
  wallTime: ISODate(...),       // Actual wall clock time
  
  documentKey: { _id: 1 },  // Which document changed
  
  ns: {  // Namespace (database.collection)
    db: 'shop',
    coll: 'customers'
  },
  
  // FOR UPDATES - THE IMPORTANT PART:
  updateDescription: {
    updatedFields: { name: 'Ritu' },  // ← DIFF!
    removedFields: [],                 // Removed fields
    truncatedArrays: []                // Truncated arrays
  },
  
  fullDocument: { _id: 1, name: 'Ritu', location: 'Hyd' }  // Current state
}
```

---

## **Performance Considerations**

1. **Index on documentKey._id** for fast lookups:
```javascript
db.changes.createIndex({ "documentKey._id": 1, "clusterTime": 1 })
```

2. **TTL Index** to auto-delete old audits:
```javascript
// Delete audits older than 90 days
db.changes.createIndex({ "wallTime": 1 }, { expireAfterSeconds: 7776000 })
```

3. **Query by operation type**:
```javascript
db.changes.createIndex({ "operationType": 1, "wallTime": -1 })
```

---

## **Summary**

✅ **MongoDB Source**: RUNNING  
✅ **MongoDB Audit Sink**: RUNNING  
✅ **Diff Capture**: WORKING - `updateDescription.updatedFields` contains only changed fields  
✅ **Kafka Topic**: `mongo.shop.customers` - flowing properly  
⚠️ **Postgres Sink**: Not working (requires custom solution for schemaless data)  

**Your audit trail with diffs is fully operational in MongoDB!** 🎉

---

## **Files**

- `connectors/mongo-source.json` - Source connector config
- `connectors/mongo-audit-history.json` - Audit sink connector config  
- `setup-connectors.sh` - Setup script
- `test-flow.sh` - End-to-end test script

---

**Need Help?**

Run a complete test:
```bash
cd /Users/mukesh.bang/projects/debezium-lab
./test-flow.sh
```

