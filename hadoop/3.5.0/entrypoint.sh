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
# The resource manager binds its addresses to that name, which is the machine's address on the cluster's network
# alone, so the agent, which carries the service gateway's requests to loopback, would find nothing on 127.0.0.1:8088.
# Every interface is what the namenode's web interface listens on by default as well; the cluster's firewall decides
# what reaches either from outside.
add_setting "YARN-SITE.XML_yarn.resourcemanager.bind-host=0.0.0.0"

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

# The daemon's heap is sized from this container's share rather than left to the JVM. Java reads its limit from
# the cgroup only where it recognises a container, and on kernels which no longer list the cgroup v2 controllers
# in /proc/cgroups it does not, and sizes the heap from the whole machine: a resource manager limited to 1GB
# would be let grow a heap past its limit, and a namenode given 2GB would never use half of it. A JVM needs
# memory beside its heap, so the heap is three quarters of the share, and never leaves less than 256MB.
memory_mb="${K_US_CONTAINER_MEMORY_MB:-${K_US_MACHINE_MEMORY_MB:-}}"
is_nodemanager=false
if [ "${1-}" = yarn ] && [ "${2-}" = nodemanager ]; then
    is_nodemanager=true
fi
if [ -n "$memory_mb" ]; then
    if [ "$is_nodemanager" = true ]; then
        # The node manager's own work is light, and what it is given beyond that is what YARN hands out.
        heap_mb=$((memory_mb / 8))
        if [ "$heap_mb" -lt 256 ]; then
            heap_mb=256
        elif [ "$heap_mb" -gt 1024 ]; then
            heap_mb=1024
        fi
    else
        heap_mb=$((memory_mb * 3 / 4))
        if [ "$heap_mb" -gt $((memory_mb - 256)) ]; then
            heap_mb=$((memory_mb - 256))
        fi
    fi
    if [ "$heap_mb" -ge 64 ]; then
        add_setting "HADOOP_HEAPSIZE_MAX=${heap_mb}m"
    fi
    # A heap the app set for itself is the one the daemon runs with, so it is what the rest is counted from.
    case "${HADOOP_HEAPSIZE_MAX:-}" in
        *[0-9]g | *[0-9]G) heap_mb=$((${HADOOP_HEAPSIZE_MAX%?} * 1024)) ;;
        *[0-9]m | *[0-9]M) heap_mb="${HADOOP_HEAPSIZE_MAX%?}" ;;
        *[0-9]) heap_mb="$HADOOP_HEAPSIZE_MAX" ;;
    esac

    # The containers YARN starts run inside the node manager's container, so they share its limit with the node
    # manager itself. What YARN may hand out is that limit less the node manager's heap and the 256MB its JVM
    # needs beside the heap; offering the whole limit would let a node's tasks fill it and be killed together.
    if [ "$is_nodemanager" = true ]; then
        yarn_mb=$((memory_mb - heap_mb - 256))
        if [ "$yarn_mb" -lt 256 ]; then
            yarn_mb=256
        fi
        add_setting "YARN-SITE.XML_yarn.nodemanager.resource.memory-mb=$yarn_mb"
    fi
fi
cpus="${K_US_CONTAINER_CPUS:-${K_US_MACHINE_CPUS:-}}"
if [ -n "$cpus" ]; then
    # A share may be fractional, while a vcore is whole: a container left 1.5 processors offers one.
    vcores="$(awk -v c="$cpus" 'BEGIN { n = int(c); if (n < 1) n = 1; print n }')"
    add_setting "YARN-SITE.XML_yarn.nodemanager.resource.cpu-vcores=$vcores"
fi

# YARN rounds every request up to its smallest allocation, 1GB unless told otherwise, which on a node of the
# template's smallest machine leaves room for one task. MapReduce's own defaults are as large: 1.5GB for a job's
# application master and 1GB for each task, which together do not fit such a node at all, so a job on a cluster of
# one core node would wait forever. These fit a node of 4GB; a job wanting more asks for it with -D.
add_setting "YARN-SITE.XML_yarn.scheduler.minimum-allocation-mb=256"
add_setting "MAPRED-SITE.XML_yarn.app.mapreduce.am.resource.mb=1024"
add_setting "MAPRED-SITE.XML_yarn.app.mapreduce.am.command-opts=-Xmx768m"
add_setting "MAPRED-SITE.XML_mapreduce.map.memory.mb=512"
add_setting "MAPRED-SITE.XML_mapreduce.reduce.memory.mb=512"
# YARN's physical memory check holds a task to what it asked for. Its virtual memory check holds it to 2.1 times
# that, which a JVM's reserved but unused address space exceeds from the start, so it kills tasks well within
# their memory.
add_setting "YARN-SITE.XML_yarn.nodemanager.vmem-check-enabled=false"

add_setting "YARN-SITE.XML_yarn.nodemanager.aux-services=mapreduce_shuffle"
add_setting "MAPRED-SITE.XML_mapreduce.framework.name=yarn"
# MapReduce tasks are started by the node manager in an environment of their own, and find Hadoop only if
# they are told where it is.
add_setting "MAPRED-SITE.XML_yarn.app.mapreduce.am.env=HADOOP_MAPRED_HOME=/opt/hadoop"
add_setting "MAPRED-SITE.XML_mapreduce.map.env=HADOOP_MAPRED_HOME=/opt/hadoop"
add_setting "MAPRED-SITE.XML_mapreduce.reduce.env=HADOOP_MAPRED_HOME=/opt/hadoop"

exec env "${settings[@]}" /opt/starter.sh "$@"
