#!/usr/bin/env bash
#
# Configures Hadoop from the environment a kopernik.us cluster app gives its containers, then hands over to
# the upstream entry point, which turns the <FILE>.<EXT>_<property> variables into XML and runs the daemon
# named in the arguments.
#
# Each value is composed only when the cluster did not state it, so anything here can be overridden through
# runtimeProps.env or a container's own env without this script putting it back.
#
# The settings are passed through env rather than exported: Hadoop's names hold dots and dashes, which are
# not names a shell can export, while env and Docker both take them as they are.
set -euo pipefail

settings=()

# Adds one NAME=VALUE setting, unless the environment already holds that name.
add_setting() {
    local assignment="$1"
    local name="${assignment%%=*}"
    # printenv reads names the shell cannot, which is every name Hadoop uses here.
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

# HDFS and YARN each need the master by name. The name resolves through the hosts file the node is given,
# which the API keeps current as the cluster's machines report their addresses.
add_setting "CORE-SITE.XML_fs.defaultFS=hdfs://$master:8020"
add_setting "YARN-SITE.XML_yarn.resourcemanager.hostname=$master"

add_setting "HDFS-SITE.XML_dfs.namenode.name.dir=file:///data/namenode"
add_setting "HDFS-SITE.XML_dfs.datanode.data.dir=file:///data/datanode"

# A block cannot be held on more nodes than the cluster has, and HDFS reports a file it cannot replicate as
# under-replicated for as long as it exists. Three is HDFS's own default and as many as it wants.
cores="${K_US_CORE_NODE_COUNT:-1}"
replication="$cores"
if [ "$replication" -gt 3 ]; then
    replication=3
fi
if [ "$replication" -lt 1 ]; then
    replication=1
fi
add_setting "HDFS-SITE.XML_dfs.replication=$replication"

# YARN hands out what the node manager says it has, and what it has is this container's share of the machine
# rather than the machine. A container told nothing of its share is one the app put no limit on, which is the
# whole machine.
memory_mb="${K_US_CONTAINER_MEMORY_MB:-${K_US_MACHINE_MEMORY_MB:-}}"
if [ -n "$memory_mb" ]; then
    add_setting "YARN-SITE.XML_yarn.nodemanager.resource.memory-mb=$memory_mb"
fi
cpus="${K_US_CONTAINER_CPUS:-${K_US_MACHINE_CPUS:-}}"
if [ -n "$cpus" ]; then
    # A share may be fractional, while a vcore is whole: a container left 1.5 processors offers one.
    vcores="$(awk -v c="$cpus" 'BEGIN { n = int(c); if (n < 1) n = 1; print n }')"
    add_setting "YARN-SITE.XML_yarn.nodemanager.resource.cpu-vcores=$vcores"
fi

add_setting "YARN-SITE.XML_yarn.nodemanager.aux-services=mapreduce_shuffle"
add_setting "MAPRED-SITE.XML_mapreduce.framework.name=yarn"
# MapReduce tasks are started by the node manager in an environment of their own, and find Hadoop only if
# they are told where it is.
add_setting "MAPRED-SITE.XML_yarn.app.mapreduce.am.env=HADOOP_MAPRED_HOME=/opt/hadoop"
add_setting "MAPRED-SITE.XML_mapreduce.map.env=HADOOP_MAPRED_HOME=/opt/hadoop"
add_setting "MAPRED-SITE.XML_mapreduce.reduce.env=HADOOP_MAPRED_HOME=/opt/hadoop"

exec env "${settings[@]}" /opt/starter.sh "$@"
