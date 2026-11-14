#!/usr/bin/env bash
# Build with Maven (needs internet once to fetch hadoop-client)
set -e
cd "$(dirname "$0")/.."
mvn -q clean package
echo "Built target/keyword-search-1.0.jar"
