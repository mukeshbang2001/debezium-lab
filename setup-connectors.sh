#!/bin/bash

# Setup script for Debezium Lab connectors

echo "================================================"
echo "Debezium Lab - Connector Setup"
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Wait for Kafka Connect to be ready
echo -e "\n${YELLOW}1. Checking Kafka Connect status...${NC}"
until curl -s http://localhost:8083/ > /dev/null; do
  echo "Waiting for Kafka Connect to be ready..."
  sleep 2
done
echo -e "${GREEN}✓ Kafka Connect is ready${NC}"

# Delete existing connectors
echo -e "\n${YELLOW}2. Removing old connectors...${NC}"
curl -s -X DELETE http://localhost:8083/connectors/mongo-cdc 2>/dev/null
curl -s -X DELETE http://localhost:8083/connectors/pg-sink 2>/dev/null
curl -s -X DELETE http://localhost:8083/connectors/mongo-source 2>/dev/null
curl -s -X DELETE http://localhost:8083/connectors/mongo-sink 2>/dev/null
sleep 2
echo -e "${GREEN}✓ Old connectors removed${NC}"

# Register MongoDB Source Connector
echo -e "\n${YELLOW}3. Registering MongoDB Source Connector...${NC}"
RESPONSE=$(curl -s -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/mongo-source.json)

if echo "$RESPONSE" | grep -q '"name"'; then
  echo -e "${GREEN}✓ MongoDB Source Connector registered successfully${NC}"
else
  echo -e "${RED}✗ Failed to register MongoDB Source Connector${NC}"
  echo "$RESPONSE" | jq .
fi

# Wait a bit
sleep 3

# Register MongoDB Sink Connector (to auditdb.audit_trail)
echo -e "\n${YELLOW}4. Registering MongoDB Sink Connector...${NC}"
RESPONSE=$(curl -s -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/mongo-sink.json)

if echo "$RESPONSE" | grep -q '"name"'; then
  echo -e "${GREEN}✓ MongoDB Sink Connector registered successfully${NC}"
else
  echo -e "${RED}✗ Failed to register MongoDB Sink Connector${NC}"
  echo "$RESPONSE" | jq .
fi

# Check connector status
echo -e "\n${YELLOW}5. Checking connector status...${NC}"
sleep 3

echo -e "\n--- MongoDB Source Connector Status ---"
curl -s http://localhost:8083/connectors/mongo-source/status | jq '{name: .name, connector_state: .connector.state, task_state: .tasks[0].state}'

echo -e "\n--- MongoDB Sink Connector Status ---"
curl -s http://localhost:8083/connectors/mongo-sink/status | jq '{name: .name, connector_state: .connector.state, task_state: .tasks[0].state}'

# List all connectors
echo -e "\n${YELLOW}6. All registered connectors:${NC}"
curl -s http://localhost:8083/connectors | jq .

echo -e "\n================================================"
echo -e "${GREEN}Setup complete!${NC}"
echo -e "================================================"
echo ""
echo "Next steps:"
echo "1. Insert data into MongoDB:"
echo "   docker exec mongodb mongosh shop --eval 'db.customers.insertOne({_id: 100, name: \"Test User\", age: 25})'"
echo ""
echo "2. Check Kafka topic:"
echo "   docker exec kafka-1 kafka-console-consumer --bootstrap-server kafka:9092 --topic mongo.shop.customers --from-beginning"
echo ""
echo "3. Check MongoDB audit trail:"
echo "   docker exec mongodb mongosh auditdb --eval 'db.audit_trail.find().pretty()'"
echo ""

