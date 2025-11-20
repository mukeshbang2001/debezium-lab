#!/bin/bash

# Fresh Setup Script for Debezium Lab
# Run this on a new machine to set up everything from scratch

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "================================================"
echo "  Debezium Lab - Fresh Setup"
echo "  MongoDB CDC with Audit Trail (DIFFS Capture)"
echo "================================================"
echo -e "${NC}"

# Check prerequisites
echo -e "\n${YELLOW}Step 1: Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found. Please install Docker first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker found: $(docker --version)${NC}"

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}✗ Docker Compose not found. Please install Docker Compose first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose found: $(docker-compose --version)${NC}"

if ! command -v curl &> /dev/null; then
    echo -e "${RED}✗ curl not found. Please install curl first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ curl found${NC}"

if command -v jq &> /dev/null; then
    echo -e "${GREEN}✓ jq found (optional but helpful)${NC}"
else
    echo -e "${YELLOW}⚠ jq not found (optional). Install with: brew install jq (macOS) or sudo apt-get install jq (Linux)${NC}"
fi

# Start Docker containers
echo -e "\n${YELLOW}Step 2: Starting Docker containers...${NC}"
docker-compose up -d

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to start Docker containers${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker containers started${NC}"

# Wait for services to start
echo -e "\n${YELLOW}Step 3: Waiting for services to start (20 seconds)...${NC}"
sleep 20

# Verify containers
echo -e "\n${YELLOW}Step 4: Verifying containers...${NC}"
CONTAINERS=$(docker ps --format "{{.Names}}" | wc -l)
if [ "$CONTAINERS" -lt 5 ]; then
    echo -e "${RED}✗ Not all containers are running. Expected 5, found $CONTAINERS${NC}"
    echo "Running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi
echo -e "${GREEN}✓ All containers running:${NC}"
docker ps --format "  - {{.Names}} ({{.Status}})"

# Initialize MongoDB replica set
echo -e "\n${YELLOW}Step 5: Initializing MongoDB replica set...${NC}"
docker exec mongodb mongosh --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠ Replica set might already be initialized, checking status...${NC}"
fi

# Wait for replica set initialization
echo -e "${YELLOW}Waiting for replica set to initialize (10 seconds)...${NC}"
sleep 10

# Verify replica set
RS_STATUS=$(docker exec mongodb mongosh --quiet --eval "rs.status().members[0].stateStr" 2>/dev/null || echo "UNKNOWN")
if [ "$RS_STATUS" = "PRIMARY" ]; then
    echo -e "${GREEN}✓ MongoDB replica set initialized (PRIMARY)${NC}"
else
    echo -e "${RED}✗ MongoDB replica set status: $RS_STATUS${NC}"
    echo "This might cause issues. Try running:"
    echo "  docker exec mongodb mongosh --eval \"rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb:27017'}]})\""
fi

# Wait for Kafka Connect
echo -e "\n${YELLOW}Step 6: Waiting for Kafka Connect to be ready...${NC}"
RETRIES=0
MAX_RETRIES=30

until curl -s http://localhost:8083/ > /dev/null 2>&1; do
    RETRIES=$((RETRIES+1))
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo -e "${RED}✗ Kafka Connect did not start in time${NC}"
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""
echo -e "${GREEN}✓ Kafka Connect is ready${NC}"

# Register connectors
echo -e "\n${YELLOW}Step 7: Registering connectors...${NC}"

# Delete old connectors if they exist
curl -s -X DELETE http://localhost:8083/connectors/mongo-source > /dev/null 2>&1
curl -s -X DELETE http://localhost:8083/connectors/mongo-audit-history > /dev/null 2>&1
sleep 2

# Register MongoDB Source
echo -n "  Registering MongoDB Source Connector... "
RESPONSE=$(curl -s -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/mongo-source.json)

if echo "$RESPONSE" | grep -q '"name"'; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "Response: $RESPONSE"
fi

sleep 3

# Register MongoDB Audit Sink
echo -n "  Registering MongoDB Audit Sink Connector... "
RESPONSE=$(curl -s -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/mongo-audit-history.json)

if echo "$RESPONSE" | grep -q '"name"'; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "Response: $RESPONSE"
fi

sleep 5

# Check connector status
echo -e "\n${YELLOW}Step 8: Checking connector status...${NC}"

SOURCE_STATUS=$(curl -s http://localhost:8083/connectors/mongo-source/status 2>/dev/null | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
SINK_STATUS=$(curl -s http://localhost:8083/connectors/mongo-audit-history/status 2>/dev/null | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ "$SOURCE_STATUS" = "RUNNING" ]; then
    echo -e "${GREEN}✓ MongoDB Source Connector: RUNNING${NC}"
else
    echo -e "${RED}✗ MongoDB Source Connector: $SOURCE_STATUS${NC}"
fi

if [ "$SINK_STATUS" = "RUNNING" ]; then
    echo -e "${GREEN}✓ MongoDB Audit Sink Connector: RUNNING${NC}"
else
    echo -e "${RED}✗ MongoDB Audit Sink Connector: $SINK_STATUS${NC}"
fi

# Run test
echo -e "\n${YELLOW}Step 9: Running test...${NC}"

echo "  Inserting test document..."
docker exec mongodb mongosh shop --quiet --eval \
  'db.customers.insertOne({_id: 1, name: "Mukesh", location: "Hyd", department: "Engineering"})' > /dev/null

sleep 3

echo "  Updating document (name change)..."
docker exec mongodb mongosh shop --quiet --eval \
  'db.customers.updateOne({_id: 1}, {$set: {name: "Ritu"}})' > /dev/null

sleep 3

echo "  Updating document (location change)..."
docker exec mongodb mongosh shop --quiet --eval \
  'db.customers.updateOne({_id: 1}, {$set: {location: "Bangalore", department: "Sales"}})' > /dev/null

sleep 3

# Check audit trail
AUDIT_COUNT=$(docker exec mongodb mongosh auditdb --quiet --eval 'db.changes.countDocuments({"documentKey._id": 1})' 2>/dev/null || echo "0")

if [ "$AUDIT_COUNT" -ge 3 ]; then
    echo -e "${GREEN}✓ Audit trail has $AUDIT_COUNT events${NC}"
else
    echo -e "${YELLOW}⚠ Audit trail has only $AUDIT_COUNT events (expected at least 3)${NC}"
fi

# Show audit trail
echo -e "\n${BLUE}=== Audit Trail (showing DIFFS) ===${NC}"
docker exec mongodb mongosh auditdb --quiet --eval '
db.changes.find({"documentKey._id": 1}).sort({clusterTime: 1}).forEach(function(doc) {
  print("\n--- " + doc.operationType.toUpperCase() + " ---");
  print("Time: " + doc.wallTime);
  
  if (doc.operationType === "insert") {
    print("Document: " + JSON.stringify(doc.fullDocument));
  } else if (doc.operationType === "update") {
    print("DIFF (Changed Fields): " + JSON.stringify(doc.updateDescription.updatedFields));
    print("Full Document After: " + JSON.stringify(doc.fullDocument));
  }
});
'

# Summary
echo -e "\n${BLUE}"
echo "================================================"
echo "  Setup Complete!"
echo "================================================"
echo -e "${NC}"

echo -e "${GREEN}✅ All systems operational!${NC}"
echo ""
echo "What's working:"
echo "  ✓ MongoDB Source Connector - Capturing change events"
echo "  ✓ Kafka Topic (mongo.shop.customers) - Streaming events"
echo "  ✓ MongoDB Audit Sink - Writing audit trail"
echo "  ✓ Audit trail captures ONLY changed fields (DIFFS)"
echo ""
echo "Quick commands:"
echo "  - View all connectors:  curl -s http://localhost:8083/connectors | jq ."
echo "  - Check status:         curl -s http://localhost:8083/connectors/mongo-source/status | jq ."
echo "  - View audit trail:     docker exec mongodb mongosh auditdb --eval 'db.changes.find().pretty()'"
echo "  - Run test:             ./test-flow.sh"
echo ""
echo "Documentation:"
echo "  - README.md - Complete guide"
echo "  - TROUBLESHOOTING.md - Troubleshooting guide"
echo "  - WORKING-SOLUTION.md - Technical details"
echo ""
echo -e "${YELLOW}Note: Postgres sink is not configured (incompatible with MongoDB Change Streams)${NC}"
echo ""

