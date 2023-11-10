# Ray open source setup in SPCS
This repo automates the setup of [Ray](https://docs.ray.io/en/latest/index.html) on Snowpark Container Services. It also loads the Vicuna13B model, which has a context length of 16K tokens as a Ray Serve API on SPCS.  This model needs a lot of GPU memory while inferencing, which cannot be served on easily available GPU infrastructure. The 8 GPUs are not coming from a single expensive GPU_10 node, infact, there are two smaller GPU7 nodes, each having 4 GPUs, which are making a Ray cluster connected to a single GPU3 Ray head node. This way, we can scale with smaller instances with GPUs whenever we have high GPU memory needs. 

In the GIF below, see how big the prompt is which is being fed into the Ray Serve API deployed on SPCS, with 8 GPUs working in parallel.

![Streamlit on SPCS](images/llm_spcs_ray.mov.gif?raw=true "Streamlit on SPCS")

The following screenshot shows a static image of the GPUs in action.

![Ray on SPCS](images/ray_dashboard_once_setup.png?raw=true "Ray on SPCS") 

## Motivation

The Ray open source community and the managed Ray offering, Anyscale, have published a plethora of blog posts on why Ray makes sense for distributing workloads. The following table highlights a few of the posts that made me fall in love with Ray, and motivated me to bring Ray into SPCS.

| Area             | Topic                                                | Context                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ---------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Data Engineering | Modin with Ray                                       | On Oct 23, Snowflake announced the intent to acquire Ponder, which will boost Python capabilities in the Data Cloud. As mentioned in the Snowflake blog, Ponder maintains [Modin](https://www.snowflake.com/blog/snowpark-ml-api-python-develops-more/), a widely-used open-source library for scalable Pandas operations. Modin is able to leverage Ray on top of SPCS to distribute pandas-based operations. For more details on this topic, see [here](https://github.com/modin-project/modin/blob/master/examples/tutorial/jupyter/execution/pandas_on_ray/local/exercise_2.ipynb). I tested open source Modin on Ray within SPCS and saw nice performance improvements compared to pandas, but that’s a blog topic for another day. |
| AI / ML          | Deep Learning batch inference                        | In [this post](https://www.anyscale.com/blog/offline-batch-inference-comparing-ray-apache-spark-and-sagemaker) from the Anyscale team, benchmarking was performed on deep learning batch inferencing on Ray vs Spark (Databricks runtime v12.0, with Apache Spark 3.3.1). IRay outperformed Spark by 2x in a Spark single cluster setup, and 3.2x in a Spark multi-cluster setup.                                                                                                                                                                                                                                                                                                                                                        |
| AI / ML          | Distributed Model Training and Hyperparameter Tuning | Ray enables data scientists to perform distributed model training and hyperparameter tuning. For more details, see [here](https://xgboost.readthedocs.io/en/stable/tutorials/ray.html) and [here](https://docs.ray.io/en/latest/train/examples/horovod/horovod_example.html).                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| LLM              | Serving LLM APIs on Ray Serve                        | With Ray Serve continuous batching and vLLM, [this post](https://www.anyscale.com/blog/continuous-batching-llm-inference) shows how LLM inference can be 23x faster with reduced p50 latency by using continuous batching functionality in Ray Serve, combined with vLLM.                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| LLM              | Parallel fine tuning of LLMs                         | With Ray TorchTrainer, LLM practitioners can perform parallel fine-tuning (a full parameter or LoRA) on open source LLMs. See [here](https://github.com/ray-project/ray/tree/master/doc/source/templates/04_finetuning_llms_with_deepspeed) for an example where Llama-2 fine tuning (7B, 13B or 70B) is demonstrated using TorchTrainer and DeepSpeed ZeRO-3 strategy.                                                                                                                                                                                                                                                                                                                                                                  |
| General          | Observability: Ray Dashboards                        | Ray provides a very nice dashboard for different types of views, such as monitoring resource utilization, monitoring job status, logs, and error messages for tasks and actors, as well as monitoring Ray Serve applications. For more details, see [here](https://docs.ray.io/en/latest/ray-observability/getting-started.html).                                                                                                                                                                                                                                                                                                                                                                                                        |
| Use cases        | Companies moving to Ray                              | There are public sessions that talk about how [Amazon](https://www.youtube.com/watch?v=u1XqELIRabI) performed an exabyte-scale migration from Spark to Ray, and how Instacart is [building their ML platform](https://www.youtube.com/watch?v=VTqM16UGs44) as well as [scaling ML fulfillment](https://www.youtube.com/watch?v=3t26ucTy0Rs&t=1s) on Ray                                                                                                                                                                                                                                                                                                                                                                                  |


## Usage
Once this setup is complete, we can interact with the Vicuna 13B (16K) model in one of the two ways.
1. Streamlit in SPCS app: 
![Streamlit on SPCS](images/llm_spcs_ray.mov.gif?raw=true "Streamlit on SPCS") Go through the instructions below to set it up. This streamlit app also features a streamlit feedback component so that users can provide feedback on the LLM output. The feedback is stored in a snowflake table and the results can be seen in the Model Monitoring table within Streamlit UI.
2. Alternatively, you can also interact with the model through notebook within the SPCS setup. Refer to `ui/notebooks/test_local_vicuna13b_16ktokens_chat.ipynb`.

## Setup Pre-requisites
1. Docker
2. SnowSQL. Installation for installing here: https://docs.snowflake.com/en/user-guide/snowsql-install-config. After installation, please check you are able to run `snowsql -v` in a new terminal. If that command doesn't work, it means that the terminal is not able to look up the installed snowsql. In that case, after snowsql installation, put an alias to snowsql in ~/.bash_profile and run `source ~/.bash_profile` before going ahead with the steps below.
3. Access to Snowpark Container Services in Private Preview. Note that you must have the ability to create a GPU_3 compute pool with 1 node and one GPU_7 compute pool with 2 nodes. 

Note that this setup has been tested on MacOS Ventura 13.6.

## Setup instructions
1. Execute these statements in snowsight or visual studio extension for Snowflake. Change to your database and schema but don't change anything else.
    ```
    create database if not exists MYDB;
    use database MYDB;
    create schema if not exists vicuna13bonrayserve;
    use schema vicuna13bonrayserve;
    create stage if not exists SPEC_STAGE;
    create image repository if not exists LLM_REPO;
    SHOW IMAGE REPOSITORIES IN SCHEMA;
    ```
    Note down the result of the last statement.
2. Setup snowsql and give the connection a name. In my case, I added the following code block to the `~/.snowsql/config`, with the connection name as fcto.
    ```
    [connections.fcto]
    accountname = XXX
    username = XXX
    password = XXX
    warehouse = XXX
    dbname = XXX
    schemaname = XXX
    rolename = XXX
    ```
3. Update REGISTRY_URL_BASE in `bin/do_login.sh`. Once updated, please run `sh bin/do_login.sh` to login into docker.
4. Update following variables in `configure_project.sh`.
    ```
    #these variables definitely need to be changed
    repository_url="myaccount.registry.snowflakecomputing.com/mydb/vicuna13bonrayserve/llm_repo"
    database="mydb"
    schema="vicuna13bonrayserve"
    spec_stage="spec_stage"
    hf_token="X"
    snowsql_connection_name=fcto

    #these variables are good enough for the Vicuna model on Ray Serve in SPCS. No need to change
    num_ray_workers=0
    num_additional_special_ray_workers_for_ray_serve=2
    ray_head_node_type=GPU_3
    ray_worker_node_type=NA
    special_ray_worker_for_ray_serve_node_type=GPU_7
    default_compute_pool_keep_alive_secs=120
    ray_head_compute_pool_name=VICUNA13B_RAY_HEAD_POOL
    ray_worker_compute_pool_name=NA
    rayserve_compute_pool_name=VICUNA13B_RAY_SERVE_POOL
    streamlit_feedback_table_name=ST_FEEDBACK
    job_manifest_file=ray_serve_vllm_vicuna13b_manifest_v27.yaml
    ```
5. Make the `configure_project.sh` executable by running `chmod +x configure_project.sh`
6. There are seven options to run `configure_project.sh`. Those will be `action=update_variables`, `action=reset_variables`, `action=deploy_all`, `action=drop_all`,  `action=drop_services`, `action=deploy_streamlit` and `action=get_endpoints`. Follow this sequence:
    - Replace placeholder values in all the spec files, config files and makefiles by running `./configure_project.sh --action=update_variables`. Just FYI: you can also reset the variables to placeholder values in all the spec files, config files and makefiles by running `./configure_project.sh --action=reset_variables`. 
    <br>Note that `./configure_project.sh --action=update_variables` must be run before deploying.
    - In order to deploy everything including the compute pools, services, volumes, jobs and needed streamlit table for feedback, you can run `./configure_project.sh --action=deploy_all`. After starting up Ray, the code will deploy Vicuna 13B model on Ray Serve. This is a synchronous job, so the `configure_project.sh` execution will appear as if it is hung, when it actually is not (this should take around 10 minutes to fully deploy Vicuna 13B model on Ray Serve). In order to see its status, either 
        * Navigate to Snowsight Query History and look for the query `EXECUTE SERVICE IN COMPUTE POOL VICUNA13B_RAY_HEAD_POOL';`
        * Or execute the commands in `get_job_status.sql`.
    - Once the script execution finishes, the script will spit out URLs for Ray head node (ray dashboard, jupyter notebook, grafana, prometheus and RayServe API); as well as URL for Streamlit app. Browse to those URLs. These URLs are public but authenticated by user's Snowflake username/password. 
        * For accessing Ray Serve API inside the SPCS Ray cluster, open the `notebook` url from terminal output in browser and upload the notebook `ui/notebooks/test_local_vicuna13b_16ktokens_chat.ipynb` to `/home/snowflake` location within jupyter.  
        * For accessing Streamlit app, open the `streamlit` url from the terminal output in browser and directly interact with the model. This streamlit app does not have any existing prompt.
        ![Streamlit on SPCS](images/llm_spcs_ray.mov.gif?raw=true "Streamlit on SPCS")
        * The Grafana dashboard will be available at `<https://GRAFANA_PUBLIC_URI>/d/rayDefaultDashboard/?var-datasource=Prometheus`. Default username/password for grafana is admin/admin. The first time you login into that url, you will see an error saying you need dashboard:read permission. Just login on the right with the admin/admin as username/password for grafana and then you will be able to see the dashboard. See that dashboard below.
        ![Grafana on SPCS](images/grafana.png?raw=true "Grafana on SPCS") 
    - In order to tear down everything including the compute pools, services, volumes, and needed streamlit table for feedback, you can run `./configure_project.sh --action=drop_all`.
    - Alternatively, in order to just tear down just the services while keeping the compute pools intact, you can run `./configure_project.sh --action=drop_services`. Note that this will result in compute pools getting suspended after 2 minutes which is the configured time after which the compute pool will auto shutdown if there is no service active on it. 


## Where to get help
This repo automates Ray on SPCS setup. If you come across any issues, please reach out to puneet.lakhanpal@snowflake.com. I would love to hear any feedback how this experience can be further improved. I will be pushing this repo on GIT, so please create an issue in GIT if you come across any issues.