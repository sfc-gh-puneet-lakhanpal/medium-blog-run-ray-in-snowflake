# Ray open source setup in SPCS
Read more about ray here: https://docs.ray.io/en/latest/index.html 

In short, Ray is an open-source unified framework for scaling AI and Python applications. It provides the compute layer for parallel processing so that you don’t need to be a distributed systems expert.

The power of Ray on SPCS is shown on the image below.

![Ray on SPCS](images/ray_dashboard_once_setup.png?raw=true "Ray on SPCS") 

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
    repository_url="sfsenorthamerica-fcto-spc.registry.snowflakecomputing.com/plakhanpal/vicuna13bonrayserve/llm_repo"
    database="plakhanpal"
    schema="vicuna13bonrayserve"
    spec_stage="spec_stage"
    hf_token="X"
    snowsql_connection_name=fcto
    
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