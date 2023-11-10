#!/bin/bash
set -e  # Exit on command errors
set -x  # Print each command before execution, useful for debugging
if [ -z "${RAY_HEAD_ADDRESS}" ]; then
    echo "Error: RAY_HEAD_ADDRESS not set"
    exit 1
fi
ray start --disable-usage-stats --address=${RAY_HEAD_ADDRESS} --resources='{"generic_label": 1}' --block