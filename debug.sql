//initialize objects
create database if not exists mydb;
use database mydb;
create schema if not exists vicuna13bonrayserve;
use schema vicuna13bonrayserve;
create stage if not exists SPEC_STAGE;
create image repository if not exists LLM_REPO;
SHOW IMAGE REPOSITORIES IN SCHEMA;

//check status of pools

show compute pools like 'VICUNA13B_RAY_HEAD_POOL';
show compute pools like 'VICUNA13B_RAY_SERVE_POOL';


//check status of services
//ray head
select v.value:containerName::varchar container_name, 
v.value:status::varchar status,
v.value:message::varchar message
from (select parse_json(system$get_service_status('spcs_ray_custom_head_service'))) t,
lateral flatten(input => t.$1) v;

//ray serve
select v.value:containerName::varchar container_name, 
v.value:status::varchar status,
v.value:message::varchar message
from (select parse_json(system$get_service_status('spcs_rayserve_custom_worker_service'))) t,
lateral flatten(input => t.$1) v;

//streamlit status
select v.value:containerName::varchar container_name, 
v.value:status::varchar status,
v.value:message::varchar message
from (select parse_json(system$get_service_status('streamlit'))) t,
lateral flatten(input => t.$1) v;

//see ray dashboard
call get_service_public_endpoints('MYDB', 'vicuna13bonrayserve', 'spcs_ray_custom_head_service');

//see streamlit
call get_service_public_endpoints('MYDB', 'vicuna13bonrayserve', 'streamlit');

//check if object exists in snowflake
call does_snowflake_object_exist('MYDB', 'vicuna13bonrayserve', 'VICUNA13B_RAY_HEAD_POOL', 'compute pools');

call does_snowflake_object_exist('MYDB', 'vicuna13bonrayserve', 'VICUNA13B_RAY_SERVE_POOL', 'compute pools');


//check logs if interested
//ray head
CALL SYSTEM$GET_SERVICE_LOGS('spcs_ray_custom_head_service', '0', 'head', 1000);
//ray workers
CALL SYSTEM$GET_SERVICE_LOGS('spcs_rayserve_custom_worker_service', '0', 'worker', 1000);

CALL SYSTEM$GET_SERVICE_LOGS('streamlit', '0', 'streamlit', 1000);