use database <<database>>;
use schema <<schema>>;

CREATE OR REPLACE PROCEDURE get_service_public_endpoints(database_name string, schema_name string, service_name string)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
execute as caller
AS
$$
def run(session, database_name, schema_name, service_name):
    show_services_sql = f"show services in schema {schema_name}"
    _ = session.sql(f"{show_services_sql};").collect()
    _ = session.sql(f"""SET query_id = (SELECT QUERY_ID FROM TABLE(information_schema.query_history_by_user())
                    WHERE QUERY_TEXT ILIKE '{show_services_sql}%'
                    ORDER BY start_time DESC
                    LIMIT 1)""").collect()
    try:
        endpoints_snowdf = session.sql(f"SELECT PARSE_JSON(\"public_endpoints\")::VARIANT AS ENDPOINTS FROM TABLE(RESULT_SCAN($query_id)) WHERE \"database_name\" = UPPER('{database_name}') AND \"schema_name\" = UPPER('{schema_name}') AND \"name\" = UPPER('{service_name}')")
        endpoint_results = endpoints_snowdf.collect()
        if len(endpoint_results)==0:
            return {}
        else:
            return endpoint_results[0]['ENDPOINTS']
    except Exception as e:
        return "not ready"
$$;