#!/usr/bin/env bash
#
# Configures Spark from the environment a kopernik.us cluster app gives its containers, then hands over to the
# Hadoop entry point beside it, which configures HDFS and YARN the same way and runs the daemon named in the
# arguments.
#
# Spark's defaults reach spark-defaults.conf through the upstream image's own conversion of variables: a
# SPARK-DEFAULTS.PROPERTIES_<property> variable is written into spark-defaults.properties in the Hadoop
# configuration directory, which the Dockerfile links spark-defaults.conf to, as Java properties Spark reads.
#
# Each value is composed only when the cluster did not state it, so anything here can be overridden through
# runtimeProps.env or a container's own env without this script putting it back. The settings are passed through env
# rather than exported, as the Hadoop entry point passes its own, because their names are not names a shell can
# export; that entry point leaves a name it finds in its environment alone, so what is set here stays set.
set -euo pipefail

settings=()

# Adds one NAME=VALUE setting, unless the environment already holds that name.
add_setting() {
    local assignment="$1"
    local name="${assignment%%=*}"
    # printenv reads names the shell cannot, which is every name Spark and Hadoop use here.
    if printenv "$name" >/dev/null 2>&1; then
        return
    fi
    settings+=("$assignment")
}

masters="${K_US_MASTER_HOSTS:-}"
master="${masters%%,*}"
if [ -z "$master" ]; then
    echo "K_US_MASTER_HOSTS is empty: this image runs as a kopernik.us cluster app, which names the" \
        "cluster's master nodes to every container" >&2
    exit 1
fi

# A job is submitted to YARN, whose resource manager is on the first master, as is the namenode keeping the event
# logs the history server reads.
add_setting "SPARK-DEFAULTS.PROPERTIES_spark.master=yarn"
add_setting "SPARK-DEFAULTS.PROPERTIES_spark.eventLog.enabled=true"
add_setting "SPARK-DEFAULTS.PROPERTIES_spark.eventLog.dir=hdfs://$master:8020/spark-events"
add_setting "SPARK-DEFAULTS.PROPERTIES_spark.history.fs.logDirectory=hdfs://$master:8020/spark-events"
add_setting "SPARK-DEFAULTS.PROPERTIES_spark.yarn.historyServer.address=$master:18080"

# Every node runs this image, so Spark's jars are already where an executor starts. Without this a job uploads all of
# them to HDFS before it runs, a few hundred megabytes for every submission.
add_setting "SPARK-DEFAULTS.PROPERTIES_spark.yarn.jars=local:/opt/spark/jars/*"

# Executors come and go with the work, and the shuffle service in each node manager keeps serving the shuffle files an
# executor wrote after the executor is gone, so one released while idle loses nothing the job still needs.
add_setting "SPARK-DEFAULTS.PROPERTIES_spark.dynamicAllocation.enabled=true"
add_setting "SPARK-DEFAULTS.PROPERTIES_spark.shuffle.service.enabled=true"
add_setting "YARN-SITE.XML_yarn.nodemanager.aux-services=mapreduce_shuffle,spark_shuffle"
add_setting "YARN-SITE.XML_yarn.nodemanager.aux-services.spark_shuffle.class=org.apache.spark.network.yarn.YarnShuffleService"

exec env "${settings[@]}" /opt/kopernik/entrypoint.sh "$@"
