#!/usr/bin/env bash
#
# Sizes MySQL to the share of the machine a kopernik.us app gives its container, then hands over to the upstream
# entry point unchanged, which initializes the data directory on first start and runs the server.
#
# The upstream image starts with the defaults its publisher chose for a laptop: a 128 MB InnoDB buffer pool,
# however large the machine. The pool is where InnoDB keeps the data and indexes it reads, so a pool much smaller
# than the machine leaves the memory a customer pays for unused and sends every read that misses it to disk.
#
# The share is read on every start rather than fixed when the app was created, so a machine resized under the app
# is used to its new size on the next start. Nothing is sized where the share is not told, which is the image run
# outside kopernik.us, and a size the app states itself is never overridden.
set -euo pipefail

# Whether the arguments already state an option, in either of the spellings mysqld accepts for it.
states_option() {
    local dashed="$1" underscored="${1//-/_}" arg
    for arg in "${args[@]}"; do
        case "$arg" in
            --"$dashed" | --"$dashed"=* | --"$underscored" | --"$underscored"=*) return 0 ;;
        esac
    done
    return 1
}

# The pool InnoDB's own innodb_dedicated_server would choose for a server given this much memory, from the share
# of the container rather than from what the server detects: inside a container it may see the whole machine.
# MySQL rounds the size up to a multiple of its chunk size, so the pool it reports may be a little larger.
buffer_pool_mb() {
    local memory_mb="$1"
    if [ "$memory_mb" -lt 1024 ]; then
        echo 128
    elif [ "$memory_mb" -le 4096 ]; then
        echo $((memory_mb / 2))
    else
        echo $((memory_mb * 3 / 4))
    fi
}

args=("$@")

# Only the server is sized. The image also runs a client or a shell when asked to, and the upstream entry point
# takes arguments starting with a dash as options of mysqld.
runs_server=false
case "${1:-}" in
    mysqld | -*) runs_server=true ;;
esac

memory_mb="${K_US_CONTAINER_MEMORY_MB:-${K_US_MACHINE_MEMORY_MB:-}}"
if $runs_server && [ -n "$memory_mb" ] && ! states_option innodb-buffer-pool-size; then
    pool_mb="$(buffer_pool_mb "$memory_mb")"
    echo "Sizing the InnoDB buffer pool to ${pool_mb} MB of the container's ${memory_mb} MB." >&2
    args+=("--innodb-buffer-pool-size=${pool_mb}M")
fi

exec docker-entrypoint.sh "${args[@]}"
