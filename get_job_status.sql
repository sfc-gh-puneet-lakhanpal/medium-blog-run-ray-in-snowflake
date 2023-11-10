use database MYDB;

use schema vicuna13bonrayserve;

SET job_id = (SELECT QUERY_ID FROM TABLE(information_schema.query_history_by_user())
WHERE QUERY_TEXT ILIKE 'EXECUTE SERVICE IN COMPUTE POOL VICUNA13B_RAY_HEAD_POOL%'
ORDER BY start_time DESC
LIMIT 1);

SHOW VARIABLES LIKE 'job_id';

call system$get_job_status($job_id);

call system$GET_JOB_LOGS($job_id, 'vllm', 1000);
