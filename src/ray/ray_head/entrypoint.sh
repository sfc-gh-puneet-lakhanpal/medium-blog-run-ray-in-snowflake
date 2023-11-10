#!/bin/bash
set -e  # Exit on command errors
set -x  # Print each command before execution, useful for debugging
if [ -z "${ENV_RAY_GRAFANA_HOST}" ]; then
    echo "Error: ENV_RAY_GRAFANA_HOST not set"
    exit 1
fi
if [ -z "${ENV_RAY_PROMETHEUS_HOST}" ]; then
    echo "Error: ENV_RAY_PROMETHEUS_HOST not set"
    exit 1
fi
export RAY_GRAFANA_HOST=$ENV_RAY_GRAFANA_HOST
export RAY_PROMETHEUS_HOST=$ENV_RAY_PROMETHEUS_HOST
export log_dir="/raylogs/ray"
echo "Making log directory $log_dir..."
mkdir -p $log_dir

jupyter lab --generate-config
nohup jupyter lab --ip='*' --port=8888 --no-browser --allow-root --NotebookApp.password='sha256:86b80ce57576:f44bf4dfc3e1b6a02dea91184eeed829d8609078395946130a3259fa6084ffe7' & 
ray start --head --disable-usage-stats --port=6379 --dashboard-host=0.0.0.0 --temp-dir=$log_dir --block