# Connector Plugins - Download Instructions

## Why Aren't Plugins in Git?

The connector plugin JAR files (~45MB) are **NOT included in the Git repository** because:
- GitHub has file size limits
- Binary files don't belong in version control
- They can be easily downloaded when needed

## Automatic Download

The `download-connectors.sh` script downloads all required plugins automatically.

**On a fresh clone:**
```bash
git clone https://github.com/mukeshbang2001/debezium-lab.git
cd debezium-lab

# Download connector plugins
./download-connectors.sh

# Then run setup
./fresh-setup.sh
```

## What Gets Downloaded

1. **MongoDB Kafka Connector** (1.11.0)
   - mongo-kafka-connect-1.11.0-all.jar (~5.4MB)
   - Source: https://github.com/mongodb/mongo-kafka/releases

2. **Debezium Scripting** (2.7.0.Final)
   - debezium-scripting-2.7.0.Final.jar (~400KB)
   - For SMT transformations
   - Source: Maven Central

3. **Debezium JDBC Sink Connector** (2.7.0.Final)
   - Multiple JAR files (~39MB total)
   - For writing to relational databases
   - Source: Maven Central

**Total size:** ~45MB

## Manual Download (If Script Fails)

### MongoDB Kafka Connector
```bash
mkdir -p connect-plugins/mongo-kafka
cd connect-plugins/mongo-kafka

curl -L https://github.com/mongodb/mongo-kafka/releases/download/r1.11.0/mongo-kafka-connect-1.11.0-all.jar \
     -o mongo-kafka-connect-1.11.0-all.jar

curl -L https://repo1.maven.org/maven2/io/debezium/debezium-scripting/2.7.0.Final/debezium-scripting-2.7.0.Final.jar \
     -o debezium-scripting-2.7.0.Final.jar

# Copy to parent for compatibility
cp mongo-kafka-connect-1.11.0-all.jar ../

cd ../..
```

### Debezium JDBC Connector
```bash
mkdir -p connect-plugins/debezium-jdbc
cd connect-plugins/debezium-jdbc

curl -L "https://search.maven.org/remotecontent?filepath=io/debezium/debezium-connector-jdbc/2.7.0.Final/debezium-connector-jdbc-2.7.0.Final-plugin.tar.gz" \
     -o jdbc.tar.gz

tar -xzf jdbc.tar.gz
mv debezium-connector-jdbc/* .
rmdir debezium-connector-jdbc
rm jdbc.tar.gz

cd ../..
```

## Verify Downloads

```bash
# Check MongoDB Kafka Connector
ls -lh connect-plugins/mongo-kafka/*.jar

# Check Debezium JDBC Connector
ls -lh connect-plugins/debezium-jdbc/*.jar | wc -l
# Should show 30+ JAR files
```

## Directory Structure

After downloading, your structure should look like:

```
connect-plugins/
├── .gitkeep
├── mongo-kafka-connect-1.11.0-all.jar (compatibility)
├── mongo-kafka/
│   ├── .gitkeep
│   ├── mongo-kafka-connect-1.11.0-all.jar
│   └── debezium-scripting-2.7.0.Final.jar
└── debezium-jdbc/
    ├── debezium-connector-jdbc-2.7.0.Final.jar
    ├── [30+ dependency JARs]
    └── ...
```

## Troubleshooting

### "curl: command not found"
```bash
# macOS
brew install curl

# Ubuntu/Debian
sudo apt-get install curl
```

### "Permission denied"
```bash
chmod +x download-connectors.sh
./download-connectors.sh
```

### Download fails
- Check your internet connection
- Try again (sometimes Maven Central is slow)
- Use manual download instructions above

### Verify after download
```bash
# Should show connector plugins
docker-compose up -d
sleep 30
curl -s http://localhost:8083/connector-plugins | \
  jq '.[] | select(.class | contains("mongodb") or contains("jdbc"))'
```

---

**Note:** The `fresh-setup.sh` script will automatically call `download-connectors.sh` if plugins are missing, so you usually don't need to run it manually.

