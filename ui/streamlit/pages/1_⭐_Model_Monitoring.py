import os
import streamlit as st
import altair as alt
from snowflake.snowpark import Session
st.set_page_config(layout="wide")
st.title("☃️ Model Monitoring: LLM Chat")
SNOW_FEEDBACK_TABLE = os.getenv("SNOWFLAKE_FEEDBACK_TABLE")
@st.cache_resource
def initiate_snowpark_conn():
    if not os.path.exists("/snowflake/session/token"):
        from dotenv import load_dotenv
        load_dotenv()
        connection_parameters = {
            "account": os.getenv("SNOWFLAKE_ACCOUNT"),
            "user": os.getenv("SNOWFLAKE_USER"),
            "password": os.getenv("SNOWFLAKE_PASSWORD"),
            "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
            "database": os.getenv("SNOWFLAKE_DATABASE"),
            "schema": os.getenv("SNOWFLAKE_SCHEMA"),
            "role": os.getenv("SNOWFLAKE_ROLE"),
            "client_session_keep_alive": True
        }
    else:
        with open("/snowflake/session/token", "r") as f:
            token = f.read()

        connection_parameters = {
            "account": os.getenv("SNOWFLAKE_ACCOUNT"),
            "host": os.getenv("SNOWFLAKE_HOST"),
            "authenticator": "oauth",
            "token": token,
            "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
            "database": os.getenv("SNOWFLAKE_DATABASE"),
            "schema": os.getenv("SNOWFLAKE_SCHEMA"),
            "client_session_keep_alive": True
        }
    snowpark_session = Session.builder.configs(connection_parameters).create()
    return snowpark_session

snowpark_session = initiate_snowpark_conn()

#@st.cache_data
def load_feedback_data():
    global snowpark_session
    sdf = snowpark_session.table(SNOW_FEEDBACK_TABLE)
    return sdf.to_pandas()

#@st.cache_data
def load_feedback_data_grouped_by_score():
    global snowpark_session
    sdf = snowpark_session.table(SNOW_FEEDBACK_TABLE).group_by('SCORE').count()
    pdf = sdf.to_pandas()
    pdf.index = pdf["SCORE"]
    pdf = pdf.drop(['SCORE'], axis=1)
    return pdf

#@st.cache_data
def load_feedback_data_line_chart():
    global snowpark_session
    sdf = snowpark_session.table(SNOW_FEEDBACK_TABLE).select("TIMESTAMP", "SCORE")
    pdf = sdf.to_pandas()
    pdf.index = pdf["TIMESTAMP"]
    pdf = pdf.drop(['TIMESTAMP'], axis=1)
    return pdf

df_feedback_data = load_feedback_data()
df_feedback_data_grouped_by_score = load_feedback_data_grouped_by_score()
df_feedback_data_line_chart = load_feedback_data_line_chart()
col1, col2 = st.columns(2)
with col1: 
    st.bar_chart(df_feedback_data_grouped_by_score)
with col2:
    st.line_chart(df_feedback_data_line_chart)
st.dataframe(df_feedback_data, use_container_width=True)