#!/bin/bash

#!/bin/bash
set -e  # Exit on command errors
set -x  # Print each command before execution, useful for debugging
wget --no-verbose -O prometheus.tgz "https://github.com/prometheus/prometheus/releases/download/v2.47.2/prometheus-2.47.2.linux-amd64.tar.gz" \
   && mkdir -p /tmp/prometheusdir \
   && tar -xf prometheus.tgz -C /tmp/prometheusdir --strip-components=1 \
   && rm prometheus.tgz

export log_dir="/raylogs/ray"
export RAY_SESSION_LATEST_DIR="$log_dir/session_latest"
export RAY_SESSION_LATEST_FILE_NAME="$RAY_SESSION_LATEST_DIR/metrics/prometheus/prometheus.yml"
until [ -f $RAY_SESSION_LATEST_FILE_NAME ]
do
    echo "Ray session metrics not ready. Waiting..."
    sleep 5
done
export PROMETHEUS_CONFIG_FILE_PATH="./prometheus.yml"
echo "printing prometheus config"
cat $PROMETHEUS_CONFIG_FILE_PATH
./tmp/prometheusdir/prometheus --config.file=$PROMETHEUS_CONFIG_FILE_PATH
tail -f /dev/null