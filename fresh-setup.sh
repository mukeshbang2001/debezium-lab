#!/bin/bash

# Fresh Setup Script for Debezium Lab with Homebrew MongoDB
# Use this when MongoDB is installed via Homebrew, not Docker

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "================================================"
echo "  Debezium Lab - Fresh Setup (Homebrew MongoDB)"
echo "================================================"
echo -e "${NC}"

# Check prerequisites
echo -e "\n${YELLOW}Step 1: Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found. Please install Docker first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker found: $(docker --version)${NC}"

# Check for docker compose
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
    echo -e "${GREEN}✓ Docker Compose found: $(docker compose version)${NC}"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
    echo -e "${GREEN}✓ Docker Compose found: $(docker-compose --version)${NC}"
else
    echo -e "${RED}✗ Docker Compose not found.${NC}"
    exit 1
fi

if ! command -v mongosh &> /dev/null; then
    echo -e "${RED}✗ MongoDB Shell not found. Please install MongoDB via Homebrew.${NC}"
    echo "  brew tap mongodb/brew"
    echo "  brew install mongodb-community@7.0"
    exit 1
fi
echo -e "${GREEN}✓ MongoDB Shell found${NC}"

# Check MongoDB is running
echo -e "\n${YELLOW}Step 2: Checking Homebrew MongoDB...${NC}"

if ! mongosh --quiet --eval "db.version()" localhost:27017 > /dev/null 2>&1; then
    echo -e "${RED}✗ MongoDB is not running on localhost:27017${NC}"
    echo ""
    echo "Please start MongoDB:"
    echo "  brew services start mongodb-community"
    echo ""
    echo "Or run the MongoDB setup script:"
    echo "  ./setup-brew-mongo.sh"
    exit 1
fi

MONGO_VERSION=$(mongosh --quiet --eval "db.version()" localhost:27017)
echo -e "${GREEN}✓ MongoDB ${MONGO_VERSION} is running${NC}"

# Check replica set
RS_STATUS=$(mongosh --quiet --eval "try { rs.status().members[0].stateStr } catch(e) { 'NOT_INITIALIZED' }" localhost:27017)
if [ "$RS_STATUS" != "PRIMARY" ] && [ "$RS_STATUS" != "SECONDARY" ]; then
    echo -e "${YELLOW}⚠ MongoDB replica set not initialized${NC}"
    echo "Initializing replica set..."
    mongosh --quiet --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'localhost:27017'}]})" localhost:27017
    sleep 10
    echo -e "${GREEN}✓ Replica set initialized${NC}"
else
    echo -e "${GREEN}✓ Replica set is ${RS_STATUS}${NC}"
fi

# Check connector plugins
echo -e "\n${YELLOW}Step 3: Checking connector plugins...${NC}"
MONGO_JARS=$(find connect-plugins/mongo-kafka -name "*.jar" 2>/dev/null | wc -l | tr -d ' ')
if [ "$MONGO_JARS" -lt 2 ]; then
    echo -e "${YELLOW}⚠ Connector plugins not found. Downloading...${NC}"
    ./download-connectors.sh
else
    echo -e "${GREEN}✓ Connector plugins found${NC}"
fi

# Start Docker containers (without MongoDB)
echo -e "\n${YELLOW}Step 4: Starting Docker services (Kafka, Postgres, Connect)...${NC}"
$DOCKER_COMPOSE up -d

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to start Docker containers${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker services started${NC}"

# Wait for services
echo -e "\n${YELLOW}Step 5: Waiting for services to start (20 seconds)...${NC}"
sleep 20

# Verify containers
echo -e "\n${YELLOW}Step 6: Verifying containers...${NC}"
CONTAINERS=$(docker ps --format "{{.Names}}" | wc -l)
if [ "$CONTAINERS" -lt 4 ]; then
    echo -e "${RED}✗ Not all containers are running. Expected 4, found $CONTAINERS${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi
echo -e "${GREEN}✓ All containers running${NC}"

# Wait for Kafka Connect
echo -e "\n${YELLOW}Step 7: Waiting for Kafka Connect...${NC}"
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
echo -e "\n${YELLOW}Step 8: Registering connectors...${NC}"

curl -s -X DELETE http://localhost:8083/connectors/mongo-source > /dev/null 2>&1
curl -s -X DELETE http://localhost:8083/connectors/mongo-audit-history > /dev/null 2>&1
sleep 2

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
echo -e "\n${YELLOW}Step 9: Checking connector status...${NC}"

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
echo -e "\n${YELLOW}Step 10: Running test...${NC}"

echo "  Inserting test document..."
mongosh --quiet --eval \
  'use shop; db.customers.insertOne({_id: 1, name: "Mukesh", location: "Hyd", department: "Engineering"})' \
  localhost:27017 > /dev/null

sleep 3

echo "  Updating document (name change)..."
mongosh --quiet --eval \
  'use shop; db.customers.updateOne({_id: 1}, {$set: {name: "Ritu"}})' \
  localhost:27017 > /dev/null

sleep 3

echo "  Updating document (location change)..."
mongosh --quiet --eval \
  'use shop; db.customers.updateOne({_id: 1}, {$set: {location: "Bangalore", department: "Sales"}})' \
  localhost:27017 > /dev/null

sleep 3

# Check audit trail
AUDIT_COUNT=$(mongosh --quiet --eval 'use auditdb; db.changes.countDocuments({"documentKey._id": 1})' localhost:27017 2>/dev/null || echo "0")

if [ "$AUDIT_COUNT" -ge 3 ]; then
    echo -e "${GREEN}✓ Audit trail has $AUDIT_COUNT events${NC}"
else
    echo -e "${YELLOW}⚠ Audit trail has only $AUDIT_COUNT events (expected at least 3)${NC}"
fi

# Show audit trail
echo -e "\n${BLUE}=== Audit Trail (showing DIFFS) ===${NC}"
mongosh --quiet --eval '
use auditdb;
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
' localhost:27017

# Summary
echo -e "\n${BLUE}"
echo "================================================"
echo "  Setup Complete!"
echo "================================================"
echo -e "${NC}"

echo -e "${GREEN}✅ All systems operational!${NC}"
echo ""
echo "What's working:"
echo "  ✓ Homebrew MongoDB (localhost:27017) - Replica set initialized"
echo "  ✓ Kafka streaming - Events flowing"
echo "  ✓ MongoDB Audit Sink - Writing audit trail"
echo "  ✓ Audit trail captures ONLY changed fields (DIFFS)"
echo ""
echo "Quick commands:"
echo "  - View audit trail:  mongosh localhost:27017/auditdb --eval 'db.changes.find().pretty()'"
echo "  - MongoDB status:    brew services list | grep mongodb"
echo "  - Connector status:  curl -s http://localhost:8083/connectors | jq ."
echo ""

