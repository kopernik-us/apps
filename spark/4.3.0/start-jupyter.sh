#!/usr/bin/env bash
#
# Runs JupyterLab on the master, whose PySpark kernel runs each notebook's Spark driver in this container, in client
# mode, with its executors in YARN on the core nodes. It runs through the image's entry point, so Spark and Hadoop are
# configured by the time a kernel reads either.
#
# JupyterLab listens on the loopback address alone and asks for no token. The containers share the machine's network,
# so listening anywhere else would offer whatever reaches the machine a shell on it, while on loopback only the agent
# reaches it, carrying requests the service gateway authorised for the account. The gateway names the service's own
# host in the requests it carries, which JupyterLab refuses from a server on loopback unless remote access is allowed.
set -euo pipefail

notebooks="/data/notebooks"

# A driver's heap, which Spark sizes at 1GB whatever the container, is a third of this container's share, so that a few
# notebooks run side by side with the server. It is never less than 512MB nor more than 4GB. Spark takes it only where
# the notebook's session states no spark.driver.memory of its own.
memory_mb="${K_US_CONTAINER_MEMORY_MB:-}"
if [ -z "${SPARK_DRIVER_MEMORY:-}" ] && [ -n "$memory_mb" ]; then
    driver_mb=$((memory_mb / 3))
    if [ "$driver_mb" -lt 512 ]; then
        driver_mb=512
    elif [ "$driver_mb" -gt 4096 ]; then
        driver_mb=4096
    fi
    export SPARK_DRIVER_MEMORY="${driver_mb}m"
fi

# Settings and workspaces are kept with the notebooks, so that they outlive the container as the notebooks do.
export JUPYTERLAB_SETTINGS_DIR="$notebooks/.jupyter/lab/user-settings"
export JUPYTERLAB_WORKSPACES_DIR="$notebooks/.jupyter/lab/workspaces"

# A kernel holds a Spark driver, and the driver holds a YARN application master, so a kernel left idle for an hour is
# shut down to give both back. Its executors are given back sooner, by dynamic allocation.
exec /opt/python/bin/jupyter lab \
    --ServerApp.ip=127.0.0.1 \
    --ServerApp.port=8888 \
    --ServerApp.open_browser=False \
    --ServerApp.allow_remote_access=True \
    --IdentityProvider.token= \
    --ServerApp.root_dir="$notebooks" \
    --MappingKernelManager.cull_idle_timeout=3600 \
    --MappingKernelManager.cull_interval=300
