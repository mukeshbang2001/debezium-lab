#!/bin/bash

# Script to download Kafka connector plugins
# Run this before starting the services if connect-plugins/ is empty

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Downloading Kafka Connector Plugins...${NC}"

# Create directories
mkdir -p connect-plugins/mongo-kafka
mkdir -p connect-plugins/debezium-jdbc

# Download MongoDB Kafka Connector (1.11.0)
echo -e "\n${YELLOW}1. Downloading MongoDB Kafka Connector (1.11.0)...${NC}"
if [ ! -f connect-plugins/mongo-kafka/mongo-kafka-connect-1.11.0-all.jar ]; then
    cd connect-plugins/mongo-kafka
    curl -L https://github.com/mongodb/mongo-kafka/releases/download/r1.11.0/mongo-kafka-connect-1.11.0-all.jar \
         -o mongo-kafka-connect-1.11.0-all.jar
    
    # Also copy to parent directory for compatibility
    cp mongo-kafka-connect-1.11.0-all.jar ../
    
    cd ../..
    echo -e "${GREEN}✓ MongoDB Kafka Connector downloaded${NC}"
else
    echo -e "${GREEN}✓ MongoDB Kafka Connector already exists${NC}"
fi

# Download Debezium Scripting (for transformations)
echo -e "\n${YELLOW}2. Downloading Debezium Scripting...${NC}"
if [ ! -f connect-plugins/mongo-kafka/debezium-scripting-2.7.0.Final.jar ]; then
    cd connect-plugins/mongo-kafka
    curl -L https://repo1.maven.org/maven2/io/debezium/debezium-scripting/2.7.0.Final/debezium-scripting-2.7.0.Final.jar \
         -o debezium-scripting-2.7.0.Final.jar
    cd ../..
    echo -e "${GREEN}✓ Debezium Scripting downloaded${NC}"
else
    echo -e "${GREEN}✓ Debezium Scripting already exists${NC}"
fi

# Download Debezium JDBC Sink Connector (2.7.0)
echo -e "\n${YELLOW}3. Downloading Debezium JDBC Sink Connector (2.7.0)...${NC}"
if [ ! -d connect-plugins/debezium-jdbc ] || [ -z "$(ls -A connect-plugins/debezium-jdbc)" ]; then
    cd connect-plugins/debezium-jdbc
    
    echo "  Downloading connector package..."
    curl -L "https://search.maven.org/remotecontent?filepath=io/debezium/debezium-connector-jdbc/2.7.0.Final/debezium-connector-jdbc-2.7.0.Final-plugin.tar.gz" \
         -o jdbc.tar.gz
    
    echo "  Extracting..."
    tar -xzf jdbc.tar.gz
    mv debezium-connector-jdbc/* .
    rmdir debezium-connector-jdbc
    rm jdbc.tar.gz
    
    cd ../..
    echo -e "${GREEN}✓ Debezium JDBC Sink Connector downloaded${NC}"
else
    echo -e "${GREEN}✓ Debezium JDBC Sink Connector already exists${NC}"
fi

# Verify downloads
echo -e "\n${YELLOW}4. Verifying downloads...${NC}"
MONGO_JAR=$(find connect-plugins/mongo-kafka -name "*.jar" | wc -l)
JDBC_JAR=$(find connect-plugins/debezium-jdbc -name "*.jar" | wc -l)

echo "  MongoDB Kafka Connector JARs: $MONGO_JAR"
echo "  Debezium JDBC Connector JARs: $JDBC_JAR"

if [ "$MONGO_JAR" -ge 2 ] && [ "$JDBC_JAR" -ge 10 ]; then
    echo -e "\n${GREEN}✓ All connector plugins downloaded successfully!${NC}"
    echo ""
    echo "Connector plugins are ready in connect-plugins/"
    echo "You can now run: ./fresh-setup.sh"
else
    echo -e "\n${RED}✗ Some connector plugins may be missing${NC}"
    echo "Expected: MongoDB Kafka (2+ JARs), Debezium JDBC (10+ JARs)"
    exit 1
fi

echo ""
echo "================================================"
echo -e "${GREEN}Download Complete!${NC}"
echo "================================================"
echo ""

