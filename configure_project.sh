#!/bin/bash

########################## You can change these variables ##############################
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


########################## Dont change from this point onwards #######################

artifacts_stage="snowml_home"
# Parse arguments
update_params="false"
push_images="false"
deploy_services="false"
deploy_model_on_ray_serve="false"
deploy_streamlit_only="false"
reverse_params="false"
suspend_all="false"
drop_all="false"
drop_services_only="false"
get_public_endpoints="false"
ACTION=""
for arg in "$@"
do
    key=${arg%%=*}
    value=${arg#*=}
    if [[ "$key" == "--action" ]]; then
        ACTION=${value};
    fi
done

case $ACTION in
"reset_variables")
    reverse_params="true"
    ;;
"update_variables")
    update_params="true"
    ;;
"drop_all")
   drop_all="true"
    ;;
"drop_services")
   drop_services_only="true"
    ;;
"get_endpoints")
   get_public_endpoints="true"
    ;;
"deploy_streamlit")
   deploy_streamlit_only="true"
    ;;
"deploy_all")
    update_params="false"
    push_images="true"
    deploy_services="true"
    deploy_model_on_ray_serve="true"
    get_public_endpoints="true"
    ;;
*)
    echo "Invalid action: ${ACTION}"
    exit 1
    ;;
esac



dir_path_project_root=$(pwd)
dir_path_grafana="./src/grafana"
dir_path_prometheus="./src/prometheus"
dir_path_ray_head="./src/ray/ray_head"
dir_path_ray_worker="./src/ray/ray_worker"
dir_path_special_ray_worker_llm="./src/ray/special_ray_worker_llm"
dir_path_ray_serve_vllm_vicuna13b="./src/ray/ray_serve_vllm_vicuna13b"
dir_path_streamlit="./ui/streamlit"

# Paths to the config files
ray_head_config_file="./src/ray/ray_head/config.env"
ray_worker_config_file="./src/ray/ray_worker/config.env"
special_ray_worker_config_file="./src/ray/special_ray_worker_llm/config.env"
ray_serve_llm_vicuna13b_config_file="./src/ray/ray_serve_vllm_vicuna13b/config.env"
grafana_config_file="./src/grafana/config.env"
prometheus_config_file="./src/prometheus/config.env"
streamlit_config_file="./ui/streamlit/config.env"

# Paths to the makefiles
ray_head_make_file="./src/ray/ray_head/Makefile"
ray_worker_make_file="./src/ray/ray_worker/Makefile"
special_ray_worker_make_file="./src/ray/special_ray_worker_llm/Makefile"
ray_serve_llm_vicuna13b_make_file="./src/ray/ray_serve_vllm_vicuna13b/Makefile"
grafana_make_file="./src/grafana/Makefile"
prometheus_make_file="./src/prometheus/Makefile"
streamlit_make_file="./ui/streamlit/Makefile"


# Paths to the spec files
ray_head_spec_file="./src/ray/ray_head/ray_head_manifest_v27.yaml"
ray_worker_spec_file="./src/ray/ray_worker/ray_worker_manifest_v27.yaml"
special_ray_worker_spec_file="./src/ray/special_ray_worker_llm/special_ray_worker_llm_manifest_v27.yaml"
ray_serve_llm_vicuna13b_spec_file="./src/ray/ray_serve_vllm_vicuna13b/ray_serve_vllm_vicuna13b_manifest_v27.yaml"
streamlit_spec_file="./ui/streamlit/streamlit.yaml"

#Path to util sql file name
configure_project_helper_sql_file_name="./configure_project_helper.sql"

wait_until_service_ready(){
    local database=${1}
    local schema=${2}
    local service_name=${3}
    local snow_connection_name=${4}
    echo "Starting: Checking status of service $service_name."
    service_not_ready=$(snowsql -c $snow_connection_name -q "select ARRAY_SIZE(array_remove(array_agg(v.value:status::varchar), 'READY'::VARIANT))>0 as not_ready_status from (select parse_json(system\$get_service_status('$database.$schema.$service_name'))) t, lateral flatten(input => t.\$1) v" -o friendly=False -o header=False -o output_format=plain -o timing=False)
    while [ "$service_not_ready" = "True" ]; do
        echo "Service $service_name not ready. Waiting..."
        sleep 10
        service_not_ready=$(snowsql -c $snow_connection_name -q "select ARRAY_SIZE(array_remove(array_agg(v.value:status::varchar), 'READY'::VARIANT))>0 as not_ready_status from (select parse_json(system\$get_service_status('$database.$schema.$service_name'))) t, lateral flatten(input => t.\$1) v" -o friendly=False -o header=False -o output_format=plain -o timing=False)
    done
    echo "Completed: Service $service_name successfully started."
}


create_spcs_container_volumes_if_not_exists() {
    local database=${1}
    local schema=${2}
    local snow_connection_name=${3}

    #create compute pool for ray head
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        create stage if not exists SNOWML_HOME ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
        create stage if not exists ray_logs ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
        "
}

drop_spcs_container_volumes() {
    local database=${1}
    local schema=${2}
    local snow_connection_name=${3}

    #create compute pool for ray head
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        drop stage if exists ray_logs;
        "
}

drop_spcs_services_and_compute_pools(){
    local database=${1}
    local schema=${2}
    local rayhead_cp_name=${3}
    local rayworker_cp_name=${4}
    local rayserve_cp_name=${5}
    local snow_connection_name=${6}
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        alter compute pool if exists $rayhead_cp_name stop all;
        alter compute pool if exists $rayworker_cp_name stop all;
        alter compute pool if exists $rayserve_cp_name stop all;
        drop compute pool if exists $rayhead_cp_name;
        drop compute pool if exists $rayworker_cp_name;
        drop compute pool if exists $rayserve_cp_name;
        drop stage if exists ray_logs;
        drop procedure if exists get_service_public_endpoints(string);
        "
}

drop_ray_worker_service_func(){
    local database=${1}
    local schema=${2}
    local snow_connection_name=${3}
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        drop service if exists spcs_ray_custom_worker_service;
        "
}

drop_streamlit_service_func(){
    local database=${1}
    local schema=${2}
    local snow_connection_name=${3}
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        drop service if exists streamlit;
        "
}

drop_ray_head_service_func(){
    local database=${1}
    local schema=${2}
    local snow_connection_name=${3}
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        drop service if exists spcs_ray_custom_head_service;
        "
}

drop_ray_special_worker_service_func(){
    local database=${1}
    local schema=${2}
    local snow_connection_name=${3}
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        drop service if exists spcs_rayserve_custom_worker_service;
        "
}

suspend_spcs_services_and_compute_pools(){
    local database=${1}
    local schema=${2}
    local rayhead_cp_name=${3}
    local rayworker_cp_name=${4}
    local rayserve_cp_name=${5}
    local snow_connection_name=${6}
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        alter compute pool $rayhead_cp_name stop all;
        alter compute pool $rayworker_cp_name stop all;
        alter compute pool $rayserve_cp_name stop all;
        alter compute pool $rayhead_cp_name suspend;
        alter compute pool $rayworker_cp_name suspend;
        alter compute pool $rayserve_cp_name suspend;
        "
}

create_spcs_utils_using_snowsql(){
    local sql_file_name=${1}
    local snow_connection_name=${2}
    snowsql -c $snow_connection_name -f $sql_file_name
}

deploy_model_on_ray_serve(){
    local database=${1}
    local schema=${2}
    local spec_stage=${3}
    local manifest_file=${4}
    local compute_pool=${5}
    local snow_connection_name=${6}
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        EXECUTE SERVICE IN COMPUTE POOL $compute_pool FROM @$spec_stage SPEC='$manifest_file';
        "

}

get_public_endpoints_for_service(){
    local service_name=${1}
    local database=${2}
    local schema=${3}
    local snow_connection_name=${4}
    public_endpoints=$(snowsql -c $snow_connection_name -q "call $database.$schema.get_service_public_endpoints('$database', '$schema', '$service_name')" -o friendly=False -o header=False -o output_format=plain -o timing=False)
    while [ "$public_endpoints" = "\"not ready"\" ]; do
        echo "Public endpoints not ready. Waiting..."
        sleep 10
        public_endpoints=$(snowsql -c $snow_connection_name -q "call $database.$schema.get_service_public_endpoints('$database', '$schema', '$service_name')" -o friendly=False -o header=False -o output_format=plain -o timing=False)
    done
    echo "Public endpoints for $service_name: $public_endpoints"
}

start_spcs_compute_pool() {
    local database=${1}
    local schema=${2}
    local compute_pool_name=${3}
    local num_nodes=${4}
    local node_type=${5}
    local keep_alive_secs=${6}
    local snow_connection_name=${7}

    #create compute pool for ray head
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        create compute pool if not exists $compute_pool_name
            min_nodes = $num_nodes 
            max_nodes = $num_nodes
            instance_family = $node_type
            auto_resume = TRUE
            KEEP_ALIVE_SECS = $keep_alive_secs
            AUTO_SUSPEND_SECS = $keep_alive_secs;
        "
}


start_spcs_service() {
    local database=${1}
    local schema=${2}
    local service_name=${3}
    local compute_pool_name=${4}
    local num_service_replicas=${5}
    local spec_stage=${6}
    local manifest_file_name=${7}
    local snow_connection_name=${8}

    #create compute pool for ray head
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        create service if not exists $service_name
            min_instances = $num_service_replicas
            max_instances = $num_service_replicas
            compute_pool = $compute_pool_name
            spec = '@$spec_stage/$manifest_file_name';
        "
        echo "Starting: Checking status of the service $service_name."
        wait_until_service_ready $database $schema $service_name $snow_connection_name
        echo "Completed: Service $service_name has been successfully started."
}

create_streamlit_feedback_table_if_not_exists() {
    local database=${1}
    local schema=${2}
    local table_name=${3}
    local snow_connection_name=${4}
    echo "Starting: Creating streamlit feedback table $table_name."
    snowsql -c $snow_connection_name -q "
        use database $database;
        use schema $schema;
        create table if not exists $table_name (
            RUN_ID string,
            TIMESTAMP timestamp_ltz,
            USER_PROMPT string,
            ASSISTANT_RESPONSE string,
            SCORE integer,
            COMMENT string
            );

        "
        echo "Completed: Finished creating streamlit feedback table $table_name."
}

update_config_file() {
    local config_file=$1
    local database=$2
    local schema=$3
    local spec_stage=$4
    local artifacts_stage=$5
    local repository_url=$6
    sed -i "" "s|<<repository_url>>|$repository_url|g" $config_file
    sed -i "" "s|<<database>>|$database|g" $config_file
    sed -i "" "s|<<schema>>|$schema|g" $config_file
    sed -i "" "s|<<spec_stage>>|$spec_stage|g" $config_file
    sed -i "" "s|<<artifacts_stage>>|$artifacts_stage|g" $config_file
    echo "Updated variables in config file: $config_file."
}

update_makefile() {
    local make_file=$1
    local snow_connection_name=$2
    sed -i "" "s|<<snowsql_connection_name>>|$snow_connection_name|g" $make_file
    echo "Updated snowsql connection name in makefile: $make_file."
}

reverse_makefile_update() {
    local make_file=$1
    local snow_connection_name=$2
    sed -i "" "s|$snow_connection_name|<<snowsql_connection_name>>|g" $make_file
    echo "Reversed to variable in makefile: $make_file."
}


reverse_config_file_update() {
    local config_file=$1
    local database=$2
    local schema=$3
    local spec_stage=$4
    local artifacts_stage=$5
    local repository_url=$6
    sed -i "" "s|$repository_url|<<repository_url>>|g" $config_file
    sed -i "" "s|$database|<<database>>|g" $config_file
    sed -i "" "s|$schema|<<schema>>|g" $config_file
    sed -i "" "s|$spec_stage|<<spec_stage>>|g" $config_file
    sed -i "" "s|$artifacts_stage|<<artifacts_stage>>|g" $config_file
    echo "Reversed to variables in config file: $config_file."
}

update_spec_file() {
    local spec_file=$1
    local artifacts_stage=$2
    local repository_url=$3
    local hf_token=$4
    sed -i "" "s|<<repository_url>>|$repository_url|g" $spec_file
    sed -i "" "s|<<artifacts_stage>>|$artifacts_stage|g" $spec_file
    sed -i "" "s|<<hf_token>>|$hf_token|g" $spec_file
    echo "Updated variables in spec file: $spec_file."
}

update_configure_project_helper_sql_file() {
    local sql_file=$1
    local database=$2
    local schema=$3
    sed -i "" "s|<<database>>|$database|g" $sql_file
    sed -i "" "s|<<schema>>|$schema|g" $sql_file
    echo "Updated variables in configure_project_helper sql file: $sql_file."
}

reverse_configure_project_helper_sql_file_update() {
    local sql_file=$1
    local database=$2
    local schema=$3
    sed -i "" "s|$database|<<database>>|g" $sql_file
    sed -i "" "s|$schema|<<schema>>|g" $sql_file
    echo "Reversed to variables in configure_project_helper sql file: $sql_file."
}

reverse_spec_file_update() {
    local spec_file=$1
    local artifacts_stage=$2
    local repository_url=$3
    local hf_token=$4
    sed -i "" "s|$repository_url|<<repository_url>>|g" $spec_file
    sed -i "" "s|$artifacts_stage|<<artifacts_stage>>|g" $spec_file
    sed -i "" "s|$hf_token|<<hf_token>>|g" $spec_file
    echo "Reversed to variables in spec file: $spec_file."
}


docker_buildandpush_plus_upload_spec_file() {
    local target_dir=$1
    local root_dir=$2
    echo "Starting: Docker container and spec file push into Snowflake from path: $target_dir."
    cd $target_dir
    echo "$pwd"
    make all
    cd $root_dir
    echo "$pwd"
    echo "Completed: Docker container and spec file pushed into Snowflake from path: $target_dir."
}

if [ "$update_params" = "true" ]
then
    echo "Started: Replacing placeholder values in config files, spec files, sql helper files and makefiles!"
    #update parameters in config files
    update_config_file $ray_head_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    update_config_file $ray_worker_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    update_config_file $special_ray_worker_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    update_config_file $ray_serve_llm_vicuna13b_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    update_config_file $grafana_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    update_config_file $prometheus_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    update_config_file $streamlit_config_file $database $schema $spec_stage $artifacts_stage $repository_url

    #update parameters in spec files
    update_spec_file $ray_head_spec_file $artifacts_stage $repository_url $hf_token
    update_spec_file $ray_worker_spec_file $artifacts_stage $repository_url $hf_token
    update_spec_file $special_ray_worker_spec_file $artifacts_stage $repository_url $hf_token
    update_spec_file $ray_serve_llm_vicuna13b_spec_file $artifacts_stage $repository_url $hf_token
    update_spec_file $streamlit_spec_file $artifacts_stage $repository_url $hf_token

    #update snowsql connection name in makefiles
    update_makefile $ray_head_make_file $snowsql_connection_name
    update_makefile $ray_worker_make_file $snowsql_connection_name
    update_makefile $special_ray_worker_make_file $snowsql_connection_name
    update_makefile $ray_serve_llm_vicuna13b_make_file $snowsql_connection_name
    update_makefile $grafana_make_file $snowsql_connection_name
    update_makefile $prometheus_make_file $snowsql_connection_name
    update_makefile $streamlit_make_file $snowsql_connection_name

    #update configure_project_helper.sql file
    update_configure_project_helper_sql_file $configure_project_helper_sql_file_name $database $schema
    echo "Completed: Placeholder values have been replaced in config files, spec files, sql helper files and makefiles!"
fi

if [ "$reverse_params" = "true" ]
then
    echo "Started: Replacing actual values with placeholder values in config files, spec files, sql helper files and makefiles!"
    #reverse parameters in config files
    reverse_config_file_update $ray_head_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    reverse_config_file_update $ray_worker_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    reverse_config_file_update $special_ray_worker_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    reverse_config_file_update $ray_serve_llm_vicuna13b_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    reverse_config_file_update $grafana_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    reverse_config_file_update $prometheus_config_file $database $schema $spec_stage $artifacts_stage $repository_url
    reverse_config_file_update $streamlit_config_file $database $schema $spec_stage $artifacts_stage $repository_url

    #reverse parameters in spec files

    reverse_spec_file_update $ray_head_spec_file $artifacts_stage $repository_url $hf_token
    reverse_spec_file_update $ray_worker_spec_file $artifacts_stage $repository_url $hf_token
    reverse_spec_file_update $special_ray_worker_spec_file $artifacts_stage $repository_url $hf_token
    reverse_spec_file_update $ray_serve_llm_vicuna13b_spec_file $artifacts_stage $repository_url $hf_token
    reverse_spec_file_update $streamlit_spec_file $artifacts_stage $repository_url $hf_token

    #reverse snowsql connection name
    reverse_makefile_update $ray_head_make_file $snowsql_connection_name
    reverse_makefile_update $ray_worker_make_file $snowsql_connection_name
    reverse_makefile_update $special_ray_worker_make_file $snowsql_connection_name
    reverse_makefile_update $ray_serve_llm_vicuna13b_make_file $snowsql_connection_name
    reverse_makefile_update $grafana_make_file $snowsql_connection_name
    reverse_makefile_update $prometheus_make_file $snowsql_connection_name
    reverse_makefile_update $streamlit_make_file $snowsql_connection_name

    #reverse sql helper file
    reverse_configure_project_helper_sql_file_update $configure_project_helper_sql_file_name $database $schema
    echo "Completed: Actual values have been replaced with placeholder values in config files, spec files, sql helper files and makefiles!"
fi

if [ "$push_images" = "true" ]
then
    echo "Started: Building docker images, pushing to Snowflake image registry and uploading spec files!"
    docker_buildandpush_plus_upload_spec_file $dir_path_grafana $dir_path_project_root
    docker_buildandpush_plus_upload_spec_file $dir_path_prometheus $dir_path_project_root
    docker_buildandpush_plus_upload_spec_file $dir_path_ray_head $dir_path_project_root
    docker_buildandpush_plus_upload_spec_file $dir_path_ray_worker $dir_path_project_root
    docker_buildandpush_plus_upload_spec_file $dir_path_special_ray_worker_llm $dir_path_project_root
    docker_buildandpush_plus_upload_spec_file $dir_path_ray_serve_vllm_vicuna13b $dir_path_project_root
    docker_buildandpush_plus_upload_spec_file $dir_path_streamlit $dir_path_project_root
    echo "Completed: Built docker images, pushed to Snowflake image registry and uploaded spec files!"

fi


if [ "$deploy_services" = "true" ]
then
    echo "Starting: Installing SPCS utils."
    create_spcs_utils_using_snowsql $configure_project_helper_sql_file_name $snowsql_connection_name
    echo "Starting: Starting up compute pools."
    start_spcs_compute_pool $database $schema $ray_head_compute_pool_name 1 $ray_head_node_type $default_compute_pool_keep_alive_secs $snowsql_connection_name
    if [ $num_ray_workers -gt 0 ]
    then
        start_spcs_compute_pool $database $schema $ray_worker_compute_pool_name $num_ray_workers $ray_worker_node_type $default_compute_pool_keep_alive_secs $snowsql_connection_name
    fi
    if [ $num_additional_special_ray_workers_for_ray_serve -gt 0 ]
    then
        start_spcs_compute_pool $database $schema $rayserve_compute_pool_name $num_additional_special_ray_workers_for_ray_serve $special_ray_worker_for_ray_serve_node_type $default_compute_pool_keep_alive_secs $snowsql_connection_name
    fi
    echo "Starting: Creating Container volumes."
    create_spcs_container_volumes_if_not_exists $database $schema $snowsql_connection_name
    echo "Starting: Creating streamlit feedback table."
    create_streamlit_feedback_table_if_not_exists $database $schema $streamlit_feedback_table_name $snowsql_connection_name
    echo "Starting: Deploying services on compute pools."
    start_spcs_service $database $schema spcs_ray_custom_head_service $ray_head_compute_pool_name 1 $spec_stage ray_head_manifest_v27.yaml $snowsql_connection_name
    if [ $num_ray_workers -gt 0 ]
    then
        start_spcs_service $database $schema spcs_ray_custom_worker_service $ray_worker_compute_pool_name $num_ray_workers $spec_stage ray_worker_manifest_v27.yaml $snowsql_connection_name
    fi
    if [ $num_additional_special_ray_workers_for_ray_serve -gt 0 ]
    then
        start_spcs_service $database $schema spcs_rayserve_custom_worker_service $rayserve_compute_pool_name $num_additional_special_ray_workers_for_ray_serve $spec_stage special_ray_worker_llm_manifest_v27.yaml $snowsql_connection_name
    fi
    start_spcs_service $database $schema streamlit $ray_head_compute_pool_name 1 $spec_stage streamlit.yaml $snowsql_connection_name
    echo "Completed: Deploying compute pool and services."
fi

if [ "$deploy_streamlit_only" = "true" ]
then
    echo "Starting: Dropping streamlit service if exists."
    drop_streamlit_service_func $database $schema $snowsql_connection_name
    echo "Starting: Creating streamlit feedback table and streamlit service."
    create_streamlit_feedback_table_if_not_exists $database $schema $streamlit_feedback_table_name $snowsql_connection_name
    start_spcs_service $database $schema streamlit $ray_head_compute_pool_name 1 $spec_stage streamlit.yaml $snowsql_connection_name
    echo "Completed: Created streamlit feedback table and streamlit service."
    get_public_endpoints_for_service streamlit $database $schema $snowsql_connection_name
    echo "Completed: Getting public endpoints."
fi

if [ "$deploy_model_on_ray_serve" = "true" ]
then
    echo "Starting: Deploying model on ray serve."
    deploy_model_on_ray_serve $database $schema $spec_stage $job_manifest_file $ray_head_compute_pool_name $snowsql_connection_name
    echo "Completed: Deployed model on ray serve."
fi

if [ "$get_public_endpoints" = "true" ]
then
    echo "Getting public endpoints for streamlit."
    get_public_endpoints_for_service streamlit $database $schema $snowsql_connection_name
    echo "Getting public endpoints for ray dashboard, notebook, grafana and prometheus."
    get_public_endpoints_for_service spcs_ray_custom_head_service $database $schema $snowsql_connection_name
    echo "Completed: Getting public endpoints."
fi

if [ "$suspend_all" = "true" ]
then
    echo "Starting: Suspending services and compute pool."
    suspend_spcs_services_and_compute_pools $database $schema $ray_head_compute_pool_name $ray_worker_compute_pool_name $rayserve_compute_pool_name $snowsql_connection_name
    echo "Completed: Suspending services and compute pool."
fi

if [ "$drop_all" = "true" ]
then
    echo "Starting: Dropping services and compute pool."
    drop_spcs_services_and_compute_pools $database $schema $ray_head_compute_pool_name $ray_worker_compute_pool_name $rayserve_compute_pool_name $snowsql_connection_name
    echo "Completed: Dropping services and compute pool."
fi

if [ "$drop_services_only" = "true" ]
then
    echo "Starting: Dropping ray head service."
    drop_ray_head_service_func $database $schema $snowsql_connection_name
    echo "Completed: Dropping ray head service."
    echo "Starting: Dropping ray worker service."
    drop_ray_worker_service_func $database $schema $snowsql_connection_name
    echo "Completed: Dropping ray worker service."
    echo "Starting: Dropping ray special worker service."
    drop_ray_special_worker_service_func $database $schema $snowsql_connection_name
    echo "Completed: Dropping ray special worker service."
    echo "Starting: Dropping streamlit service."
    drop_streamlit_service_func $database $schema $snowsql_connection_name
    echo "Completed: Dropping streamlit service."
    echo "Starting: Dropping ray log stage."
    drop_spcs_container_volumes $database $schema $snowsql_connection_name
    echo "Completed: Dropping ray log stage."
fi
