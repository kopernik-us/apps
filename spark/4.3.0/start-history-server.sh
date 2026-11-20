#!/usr/bin/env bash
#
# Runs the Spark history server, which shows the jobs a cluster ran from the event logs they left in HDFS. It runs
# through the image's entry point, so Spark and Hadoop are configured by the time this script reads either.
#
# The history server refuses to start on a log directory which does not exist, and nothing else creates it: a step
# runs before the namenode is started, and a job writes its event log only into a directory which exists. So this
# script creates it, once the namenode answers and has left safe mode, and only then starts the server.
set -euo pipefail

directory="hdfs:///spark-events"
for _ in $(seq 1 120); do
    # Writable by everyone and sticky, as /tmp is: every user submitting a job writes its log here, and none may delete
    # another's.
    if hdfs dfs -mkdir -p "$directory" 2>/dev/null && hdfs dfs -chmod 1777 "$directory" 2>/dev/null; then
        break
    fi
    sleep 5
done
if ! hdfs dfs -test -d "$directory" 2>/dev/null; then
    echo "The event log directory $directory could not be created: HDFS did not answer for ten minutes" >&2
    exit 1
fi

# The history server's heap, which Spark sizes at 1GB whatever the container, is a quarter of this container's share:
# the rest is left for the drivers of jobs submitted from this container in client mode, such as the shells. It is
# never less than 512MB, which it needs to list a few hundred jobs, nor more than 2GB.
memory_mb="${K_US_CONTAINER_MEMORY_MB:-}"
if [ -z "${SPARK_DAEMON_MEMORY:-}" ] && [ -n "$memory_mb" ]; then
    daemon_mb=$((memory_mb / 4))
    if [ "$daemon_mb" -lt 512 ]; then
        daemon_mb=512
    elif [ "$daemon_mb" -gt 2048 ]; then
        daemon_mb=2048
    fi
    export SPARK_DAEMON_MEMORY="${daemon_mb}m"
fi

exec /opt/spark/bin/spark-class org.apache.spark.deploy.history.HistoryServer
