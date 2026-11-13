#!/usr/bin/env bash
#
# Formats the HDFS namenode directory. This is the cluster's init container: a step leads the service
# containers of its node, so the namenode is started on a filesystem which already exists rather than
# formatting one while it serves.
#
# It runs through the image's entry point, so the configuration is written by the time this script reads it,
# and the directory is whatever the cluster configured rather than a second copy of the default.
#
# Formatting is skipped when the directory holds a filesystem already. A machine replaced under a running
# cluster comes back with the volume its predecessor wrote, and formatting that volume would discard the
# metadata of every file in HDFS.
set -euo pipefail

directory="$(hdfs getconf -confKey dfs.namenode.name.dir 2>/dev/null || true)"
# The configured value is a URI, and may name several directories; the namenode writes the same metadata to
# each, so the first says whether there is a filesystem here.
directory="${directory%%,*}"
directory="${directory#file://}"
if [ -z "$directory" ]; then
    directory="/data/namenode"
fi

if [ -f "$directory/current/VERSION" ]; then
    echo "The namenode at $directory is formatted already, so its metadata is kept."
    exit 0
fi

echo "Formatting the namenode at $directory."
exec hdfs namenode -format -force -nonInteractive
