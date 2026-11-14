#!/usr/bin/env bash
# Pseudo-distributed / cluster mode (HDFS + YARN running, conf/*.xml copied to $HADOOP_CONF_DIR)
set -e
cd "$(dirname "$0")/.."
KEYWORD="${1:?usage: run_hdfs.sh <keyword>}"
hdfs dfs -mkdir -p /user/$USER/news_input
hdfs dfs -put -f input/*.txt /user/$USER/news_input/
hadoop jar target/keyword-search-1.0.jar za.ac.eduvos.mr.KeywordSearchDriver \
   -D mapreduce.framework.name=yarn -D search.keyword="$KEYWORD" \
   /user/$USER/news_input /user/$USER/news_output_"$KEYWORD"
hdfs dfs -cat /user/$USER/news_output_"$KEYWORD"/part-r-*
