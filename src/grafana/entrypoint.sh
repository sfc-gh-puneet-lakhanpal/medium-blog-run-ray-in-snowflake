#!/bin/bash
set -e  # Exit on command errors
set -x  # Print each command before execution, useful for debugging
wget --no-verbose -O grafana.tgz "https://dl.grafana.com/enterprise/release/grafana-enterprise-10.2.0.linux-amd64.tar.gz" \
   && mkdir -p /tmp/grafanadir \
   && tar -xf grafana.tgz -C /tmp/grafanadir --strip-components=1 \
   && rm grafana.tgz

export log_dir="/raylogs/ray"
export RAY_SESSION_LATEST_DIR="$log_dir/session_latest"
export RAY_SESSION_LATEST_FILE_NAME="$RAY_SESSION_LATEST_DIR/metrics/grafana/grafana.ini"
until [ -f $RAY_SESSION_LATEST_FILE_NAME ]
do
    echo "Ray session metrics not ready. Waiting..."
    sleep 5
done
export GRAFANA_CONFIG_FILE_PATH="./grafana.ini"
echo "printing grafana config"
cat $GRAFANA_CONFIG_FILE_PATH
./tmp/grafanadir/bin/grafana-server --config $GRAFANA_CONFIG_FILE_PATH --homepath /tmp/grafanadir web
tail -f /dev/null