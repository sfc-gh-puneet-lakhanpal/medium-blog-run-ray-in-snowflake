#!/bin/bash

set -e  # Exit on command errors
set -x  # Print each command before execution, useful for debugging

# Check if HUGGING_FACE_MODEL is set
if [ -z "${RAY_HEAD_ADDRESS}" ]; then
    echo "Error: RAY_HEAD_ADDRESS not set"
    exit 1
fi

#ray start --disable-usage-stats --address=${RAY_HEAD_ADDRESS} --num-cpus=1 --num-gpus=4 --resources='{"custom_llm_serving_label": 1}' --block
ray start --disable-usage-stats --address=${RAY_HEAD_ADDRESS} --resources='{"custom_llm_serving_label": 1}' --block