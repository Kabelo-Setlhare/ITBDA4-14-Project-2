#!/usr/bin/env bash
# Build without Maven, using the classpath of an installed Hadoop (this is how the evidence was produced,
# with the Hadoop 3.3.4 client jars).  Usage: HADOOP_CP=$(hadoop classpath) scripts/build_nomaven.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p build/classes
javac -d build/classes -cp "${HADOOP_CP:?set HADOOP_CP}" src/main/java/za/ac/eduvos/mr/*.java
jar cf build/keyword-search.jar -C build/classes .
