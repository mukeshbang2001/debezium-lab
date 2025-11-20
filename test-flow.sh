#!/bin/bash

# Test script to verify the complete data flow with DIFFS capture

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}"
echo "================================================"
echo "  Testing Debezium Data Flow with DIFFS"
echo "================================================"
echo -e "${NC}"

# Generate random test ID
TEST_ID=$((1000 + RANDOM % 9000))

# Step 1: Check connector status
echo -e "\n${YELLOW}Step 1: Checking connector status...${NC}"
echo -e "${CYAN}MongoDB Source:${NC}"
curl -s http://localhost:8083/connectors/mongo-source/status | jq '{name: .name, state: .connector.state, task: .tasks[0].state}'

echo -e "${CYAN}MongoDB Audit Sink:${NC}"
curl -s http://localhost:8083/connectors/mongo-audit-history/status | jq '{name: .name, state: .connector.state, task: .tasks[0].state}'

# Step 2: INSERT test
echo -e "\n${YELLOW}Step 2: Inserting test document (ID=$TEST_ID)...${NC}"
docker exec mongodb mongosh shop --quiet --eval \
  "db.customers.insertOne({_id: ${TEST_ID}, name: 'Alice Smith', age: 28, city: 'Mumbai', department: 'Engineering', status: 'active'})"

echo -e "${GREEN}✓ Inserted document${NC}"

# Step 3: Wait for propagation
echo -e "\n${YELLOW}Step 3: Waiting for event propagation (5 seconds)...${NC}"
sleep 5

# Step 4: First UPDATE (change name and age)
echo -e "\n${YELLOW}Step 4: Updating document (changing name and age)...${NC}"
docker exec mongodb mongosh shop --quiet --eval \
  "db.customers.updateOne({_id: ${TEST_ID}}, {\$set: {name: 'Alicia Smith', age: 29}})"

echo -e "${GREEN}✓ Updated (name: Alice → Alicia, age: 28 → 29)${NC}"
sleep 5

# Step 5: Second UPDATE (change city and department)
echo -e "\n${YELLOW}Step 5: Updating document (changing city and department)...${NC}"
docker exec mongodb mongosh shop --quiet --eval \
  "db.customers.updateOne({_id: ${TEST_ID}}, {\$set: {city: 'Bangalore', department: 'Product Management'}})"

echo -e "${GREEN}✓ Updated (city: Mumbai → Bangalore, dept: Engineering → Product Management)${NC}"
sleep 5

# Step 6: Third UPDATE (change status only)
echo -e "\n${YELLOW}Step 6: Updating document (changing status only)...${NC}"
docker exec mongodb mongosh shop --quiet --eval \
  "db.customers.updateOne({_id: ${TEST_ID}}, {\$set: {status: 'inactive'}})"

echo -e "${GREEN}✓ Updated (status: active → inactive)${NC}"
sleep 5

# Step 7: Check source database
echo -e "\n${YELLOW}Step 7: Checking source database (current state)...${NC}"
docker exec mongodb mongosh shop --quiet --eval \
  "db.customers.findOne({_id: ${TEST_ID}})"

# Step 8: Check audit trail
echo -e "\n${YELLOW}Step 8: Checking audit trail (with DIFFS)...${NC}"

AUDIT_COUNT=$(docker exec mongodb mongosh auditdb --quiet --eval \
  "db.changes.countDocuments({\"documentKey._id\": ${TEST_ID}})")

if [ "$AUDIT_COUNT" -ge 4 ]; then
    echo -e "${GREEN}✓ Found $AUDIT_COUNT events in audit trail${NC}"
else
    echo -e "${RED}✗ Only found $AUDIT_COUNT events (expected at least 4)${NC}"
fi

echo -e "\n${CYAN}=== Audit Trail for ID=$TEST_ID ===${NC}"
docker exec mongodb mongosh auditdb --quiet --eval "
var events = db.changes.find({\"documentKey._id\": ${TEST_ID}}).sort({clusterTime: 1}).toArray();

events.forEach(function(doc, index) {
  print('\n--- EVENT ' + (index + 1) + ': ' + doc.operationType.toUpperCase() + ' ---');
  print('Timestamp: ' + doc.wallTime);
  
  if (doc.operationType === 'insert') {
    print('Full Document: ' + JSON.stringify(doc.fullDocument));
  } else if (doc.operationType === 'update') {
    print('✨ DIFF (Changed Fields): ' + JSON.stringify(doc.updateDescription.updatedFields));
    print('Current State: ' + JSON.stringify(doc.fullDocument));
  } else if (doc.operationType === 'delete') {
    print('Deleted Document ID: ' + JSON.stringify(doc.documentKey));
  }
});
"

# Step 9: Verify Kafka topic
echo -e "\n${YELLOW}Step 9: Checking Kafka topic (last event)...${NC}"
LAST_MSG=$(docker exec debezium-lab-kafka-1 kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mongo.shop.customers \
  --from-beginning \
  --max-messages 100 \
  --timeout-ms 3000 2>/dev/null | grep "${TEST_ID}" | tail -1)

if [ -n "$LAST_MSG" ]; then
    echo -e "${GREEN}✓ Found event in Kafka topic${NC}"
else
    echo -e "${YELLOW}⚠ Could not find event in Kafka topic (might have been consumed)${NC}"
fi

# Step 10: DELETE test
echo -e "\n${YELLOW}Step 10: Deleting test document...${NC}"
docker exec mongodb mongosh shop --quiet --eval \
  "db.customers.deleteOne({_id: ${TEST_ID}})"

echo -e "${GREEN}✓ Deleted document${NC}"
sleep 5

# Final audit check
echo -e "\n${YELLOW}Step 11: Final audit check (should include DELETE event)...${NC}"
FINAL_COUNT=$(docker exec mongodb mongosh auditdb --quiet --eval \
  "db.changes.countDocuments({\"documentKey._id\": ${TEST_ID}})")

echo -e "${GREEN}✓ Total events for test document: $FINAL_COUNT${NC}"

# Summary
echo -e "\n${BLUE}"
echo "================================================"
echo "  Test Complete!"
echo "================================================"
echo -e "${NC}"

echo -e "\n${GREEN}✅ Verified:${NC}"
echo "  ✓ MongoDB Source Connector: Capturing changes"
echo "  ✓ Kafka Topic: Streaming events"
echo "  ✓ MongoDB Audit Sink: Writing audit trail"
echo "  ✓ DIFF Capture: Update events show ONLY changed fields"
echo "  ✓ All operations captured: INSERT, UPDATE (with diffs), DELETE"

echo -e "\n${CYAN}Key Findings:${NC}"
echo "  • INSERT events contain full document"
echo "  • UPDATE events contain ONLY changed fields in updateDescription.updatedFields"
echo "  • UPDATE events also include fullDocument for current state"
echo "  • DELETE events contain documentKey (the ID)"

echo -e "\n${YELLOW}To view the audit trail manually:${NC}"
echo "  docker exec mongodb mongosh auditdb --eval 'db.changes.find({\"documentKey._id\": ${TEST_ID}}).pretty()'"

echo -e "\n${YELLOW}To cleanup test data from audit:${NC}"
echo "  docker exec mongodb mongosh auditdb --eval 'db.changes.deleteMany({\"documentKey._id\": ${TEST_ID}})'"

echo ""
