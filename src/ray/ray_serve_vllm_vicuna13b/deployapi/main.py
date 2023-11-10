import ray
import os
from starlette.requests import Request
from typing import List, Optional, Any
import torch
import shutil
import fire
import logging
import sys
import json
import time

from huggingface_hub.hf_api import HfFolder
import json
from typing import AsyncGenerator

from fastapi import BackgroundTasks
from starlette.requests import Request
from starlette.responses import StreamingResponse, Response
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
from vllm.sampling_params import SamplingParams
from vllm.utils import random_uuid
from ray import serve

HF_TOKEN = os.getenv("HF_TOKEN")
MODEL = os.getenv("HF_MODEL")

logger = logging.getLogger("ray.serve")
@serve.deployment(num_replicas=1, ray_actor_options={"resources": {"custom_llm_serving_label": 1}, "runtime_env":{"pip": ["accelerate>=0.20.3", "vllm==0.2.0"]}}, route_prefix="/vicuna13bapi")
class SnowflakeVLLMDeployment:
    def __init__(self, **kwargs):
        HfFolder.save_token(HF_TOKEN)
        args = AsyncEngineArgs(**kwargs)
        self.engine = AsyncLLMEngine.from_engine_args(args)

    async def stream_results(self, results_generator) -> AsyncGenerator[bytes, None]:
        num_returned = 0
        async for request_output in results_generator:
            text_outputs = [output.text for output in request_output.outputs]
            assert len(text_outputs) == 1
            text_output = text_outputs[0][num_returned:]
            ret = {"text": text_output}
            yield (json.dumps(ret) + "\n").encode("utf-8")
            num_returned += len(text_output)

    async def may_abort_request(self, request_id) -> None:
        await self.engine.abort(request_id)

    async def __call__(self, request: Request) -> Response:
        request_dict = await request.json()
        prompt = request_dict.pop("prompt")
        stream = request_dict.pop("stream", False)
        sampling_params = SamplingParams(**request_dict)
        request_id = random_uuid()
        results_generator = self.engine.generate(prompt, sampling_params, request_id)
        if stream:
            background_tasks = BackgroundTasks()
            background_tasks.add_task(self.may_abort_request, request_id)
            return StreamingResponse(
                self.stream_results(results_generator), background=background_tasks
            )

        # Non-streaming case
        final_output = None
        async for request_output in results_generator:
            if await request.is_disconnected():
                # Abort the request if the client disconnects.
                await self.engine.abort(request_id)
                return Response(status_code=499)
            final_output = request_output

        assert final_output is not None
        #prompt = final_output.prompt
        #text_outputs = [prompt + output.text for output in final_output.outputs]
        text_outputs = [output.text for output in final_output.outputs]
        ret = {"text": text_outputs}
        return Response(content=json.dumps(ret))
    
def deploy_app(url:str) -> None:
    deployment = SnowflakeVLLMDeployment.bind(model=MODEL, tensor_parallel_size=8, seed=123)
    ray.init(address=url, runtime_env={"working_dir": "."})
    serve.run(target=deployment, host="0.0.0.0", port=8000, name="vicuna13bapi")

if __name__=='__main__':
    fire.Fire()