#!/bin/bash

# Setup script for using Homebrew MongoDB instead of Docker MongoDB
# This script helps configure MongoDB installed via Homebrew

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "================================================"
echo "  Homebrew MongoDB Setup for Debezium Lab"
echo "================================================"
echo -e "${NC}"

# Check if MongoDB is installed
echo -e "\n${YELLOW}Step 1: Checking Homebrew MongoDB installation...${NC}"

if ! command -v mongosh &> /dev/null; then
    echo -e "${RED}✗ MongoDB Shell (mongosh) not found${NC}"
    echo ""
    echo "Please install MongoDB via Homebrew:"
    echo "  brew tap mongodb/brew"
    echo "  brew install mongodb-community@7.0"
    echo ""
    echo "Or if you have an older version:"
    echo "  brew services stop mongodb-community"
    echo "  brew uninstall mongodb-community"
    echo "  brew install mongodb-community@7.0"
    exit 1
fi

echo -e "${GREEN}✓ MongoDB Shell found: $(mongosh --version | head -1)${NC}"

# Check MongoDB config
echo -e "\n${YELLOW}Step 2: Checking MongoDB configuration...${NC}"

MONGO_CONF="/opt/homebrew/etc/mongod.conf"
if [ ! -f "$MONGO_CONF" ]; then
    MONGO_CONF="/usr/local/etc/mongod.conf"
fi

if [ ! -f "$MONGO_CONF" ]; then
    echo -e "${RED}✗ MongoDB config not found${NC}"
    echo "Expected location: /opt/homebrew/etc/mongod.conf or /usr/local/etc/mongod.conf"
    exit 1
fi

echo -e "${GREEN}✓ MongoDB config found: $MONGO_CONF${NC}"

# Check if replica set is configured
if grep -q "replication:" "$MONGO_CONF"; then
    echo -e "${GREEN}✓ Replication section exists in config${NC}"
else
    echo -e "${YELLOW}⚠ Replication not configured in mongod.conf${NC}"
    echo ""
    echo "MongoDB Change Data Capture requires a replica set."
    echo ""
    echo "To configure replica set, add these lines to $MONGO_CONF:"
    echo ""
    echo "replication:"
    echo "  replSetName: rs0"
    echo ""
    echo "Then restart MongoDB:"
    echo "  brew services restart mongodb-community"
    echo ""
    read -p "Would you like me to add this configuration automatically? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "" >> "$MONGO_CONF"
        echo "replication:" >> "$MONGO_CONF"
        echo "  replSetName: rs0" >> "$MONGO_CONF"
        echo -e "${GREEN}✓ Replica set configuration added${NC}"
        echo ""
        echo "Restarting MongoDB..."
        brew services restart mongodb-community
        sleep 5
    else
        echo "Please add the configuration manually and restart MongoDB."
        exit 1
    fi
fi

# Check if MongoDB is running
echo -e "\n${YELLOW}Step 3: Checking MongoDB service...${NC}"

if brew services list | grep -q "mongodb-community.*started"; then
    echo -e "${GREEN}✓ MongoDB is running${NC}"
else
    echo -e "${YELLOW}⚠ MongoDB is not running${NC}"
    echo "Starting MongoDB..."
    brew services start mongodb-community
    sleep 5
    
    if brew services list | grep -q "mongodb-community.*started"; then
        echo -e "${GREEN}✓ MongoDB started${NC}"
    else
        echo -e "${RED}✗ Failed to start MongoDB${NC}"
        exit 1
    fi
fi

# Check connection
echo -e "\n${YELLOW}Step 4: Testing MongoDB connection...${NC}"

if mongosh --quiet --eval "db.version()" localhost:27017 > /dev/null 2>&1; then
    MONGO_VERSION=$(mongosh --quiet --eval "db.version()" localhost:27017)
    echo -e "${GREEN}✓ Connected to MongoDB ${MONGO_VERSION}${NC}"
else
    echo -e "${RED}✗ Cannot connect to MongoDB on localhost:27017${NC}"
    echo "Please check if MongoDB is running:"
    echo "  brew services list | grep mongodb"
    exit 1
fi

# Initialize replica set
echo -e "\n${YELLOW}Step 5: Initializing replica set...${NC}"

RS_STATUS=$(mongosh --quiet --eval "try { rs.status().ok } catch(e) { 0 }" localhost:27017 2>/dev/null || echo "0")

if [ "$RS_STATUS" = "1" ]; then
    echo -e "${GREEN}✓ Replica set already initialized${NC}"
    RS_NAME=$(mongosh --quiet --eval "rs.status().set" localhost:27017)
    echo "  Replica set name: $RS_NAME"
else
    echo "Initializing replica set 'rs0'..."
    mongosh --quiet --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'localhost:27017'}]})" localhost:27017
    
    echo "Waiting for replica set to initialize (10 seconds)..."
    sleep 10
    
    RS_STATE=$(mongosh --quiet --eval "rs.status().members[0].stateStr" localhost:27017 2>/dev/null || echo "UNKNOWN")
    if [ "$RS_STATE" = "PRIMARY" ]; then
        echo -e "${GREEN}✓ Replica set initialized successfully (PRIMARY)${NC}"
    else
        echo -e "${YELLOW}⚠ Replica set state: $RS_STATE${NC}"
        echo "  This might be normal. Wait a few seconds and check:"
        echo "  mongosh --eval \"rs.status()\""
    fi
fi

# Create test database and collection
echo -e "\n${YELLOW}Step 6: Setting up test database...${NC}"

mongosh --quiet --eval "
use shop
db.customers.insertOne({_id: 0, name: 'System', note: 'Setup test'})
db.customers.deleteOne({_id: 0})
print('✓ Database setup complete')
" localhost:27017

# Summary
echo -e "\n${BLUE}"
echo "================================================"
echo "  MongoDB Setup Complete!"
echo "================================================"
echo -e "${NC}"

echo -e "${GREEN}✅ Homebrew MongoDB is ready for CDC!${NC}"
echo ""
echo "MongoDB Details:"
echo "  • Version: $(mongosh --version | head -1)"
echo "  • Location: localhost:27017"
echo "  • Replica Set: rs0"
echo "  • Config: $MONGO_CONF"
echo ""
echo "Next steps:"
echo "  1. Use docker-compose.brew-mongo.yml for Docker services"
echo "  2. Use connectors with .brew.json suffix"
echo "  3. Run: ./fresh-setup-brew.sh"
echo ""
echo "Check MongoDB status:"
echo "  brew services list | grep mongodb"
echo "  mongosh --eval \"rs.status()\""
echo ""

