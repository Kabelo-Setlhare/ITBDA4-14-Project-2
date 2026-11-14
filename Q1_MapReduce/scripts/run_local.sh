#!/usr/bin/env bash
# Local (standalone) mode - no HDFS/YARN needed.   Usage: scripts/run_local.sh <keyword>
set -e
cd "$(dirname "$0")/.."
KEYWORD="${1:?usage: run_local.sh <keyword>}"
hadoop jar target/keyword-search-1.0.jar za.ac.eduvos.mr.KeywordSearchDriver \
   -D search.keyword="$KEYWORD" input "output_${KEYWORD}"
cat "output_${KEYWORD}"/part-r-*
