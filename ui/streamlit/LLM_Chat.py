import pandas as pd
import streamlit as st
import os
import requests
import json
from snowflake.snowpark import Session
st.set_page_config(layout="wide")
st.title("☃️ LLM Chat")
RAY_API_URL=os.getenv("RAY_API_URL")
SNOW_FEEDBACK_TABLE = os.getenv("SNOWFLAKE_FEEDBACK_TABLE")
from uuid import uuid1
@st.cache_resource
def initiate_snowpark_conn():
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

def vicuna_api_generate_prompt(query):
    prompt = f"""[INST]
Summarize the following conversation in one paragraph. 
{query}
[/INST]
Summary: 
"""
    return prompt

def get_llm_output(url, api_input_params):
    output = requests.post(url, json=api_input_params, stream=True)
    return output

def _submit_feedback(user_response, **kwargs):
    global snowpark_session
    run_id = ""
    prompt = ""
    response = ""
    scores = {"👍": 1, "👎": 0}
    score = scores.get(user_response["score"])
    comment = ""
    if user_response["text"] is not None:
        comment = (user_response["text"]).replace("'","\\'")
    if "run_id" in kwargs:
        run_id = str(kwargs['run_id'])
    if "prompt" in kwargs:
        prompt = (kwargs['prompt']).strip().replace("'","\\'")
    if "response" in kwargs:
        response = (kwargs['response']).strip().replace("'","\\'")
    feedback_sql = f"""
        insert into {SNOW_FEEDBACK_TABLE} (RUN_ID, TIMESTAMP, USER_PROMPT, ASSISTANT_RESPONSE, SCORE, COMMENT)
        values ('{run_id}', CURRENT_TIMESTAMP, '{prompt}', '{response}', {score}, '{comment}')
    """
    print(feedback_sql)
    feedback_inserted_results = snowpark_session.sql(feedback_sql).collect()
    print(feedback_inserted_results)
    st.toast(f"Feedback submitted: {user_response}", icon=None)
    return feedback_inserted_results

def chatbot_app():
    from streamlit_feedback import streamlit_feedback
    if "messages" not in st.session_state:
        st.session_state["messages"] = [
            {"role": "assistant", "content": "Welcome to your Snowflake LLM Chat. I can summarize conversations. How can I help you?", "prompt": "NA"}
        ]
    if 'run_id' not in st.session_state:
        st.session_state.run_id = uuid1()

    messages = st.session_state.messages
    feedback_kwargs = {
        "feedback_type": "thumbs",
        "optional_text_label": "Please provide extra information",
        "on_submit": _submit_feedback,
    }

    for n, msg in enumerate(messages):
        st.chat_message(msg["role"]).write(msg["content"])

        if msg["role"] == "assistant" and n > 1:
            feedback_key = f"feedback_{int(n/2)}"

            if feedback_key not in st.session_state:
                st.session_state[feedback_key] = None

            disable_with_score = (
                st.session_state[feedback_key].get("score")
                if st.session_state[feedback_key]
                else None
            )
            streamlit_feedback(
                **feedback_kwargs,
                key=feedback_key,
                disable_with_score=disable_with_score,
                kwargs={"run_id": st.session_state.run_id,
                        "prompt": msg["prompt"],
                        "response": msg["content"]},
            )

    if prompt := st.chat_input():
        messages.append({"role": "user", "content": prompt})
        st.chat_message("user").write(prompt)
        generated_prompt = vicuna_api_generate_prompt(prompt)
        api_input_params = {
        "prompt": generated_prompt, 
        "stream": True,
        "n": 1, #Number of output sequences to return for the given prompt
        "max_tokens": 512, #Maximum number of tokens to generate per output sequence
        #"top_k": -1, #Integer that controls the number of top tokens to consider
        #"top_p": 1.0, #Float that controls the cumulative probability of the top tokens to consider
        "temperature": 0.0, #Float that controls the randomness of the sampling.
        "presence_penalty": 1.0,#Float that penalizes new tokens based on whether they appear in the generated text so far
        "frequency_penalty": 0.0,#Float that penalizes new tokens based on their frequency in the generated text so far
        "ignore_eos": False, #Whether to ignore the EOS token and continue generating tokens after the EOS token is generated
        "use_beam_search": False, #Whether to use beam search instead of sampling
        }
        with st.chat_message("assistant"):
            message_placeholder = st.empty()
            full_response = ""
            response = get_llm_output(RAY_API_URL, api_input_params)
            if response.status_code == 200:
                for chunk in response.raw.stream():
                    output = json.loads(chunk.decode("utf-8"))['text']
                    full_response += output
                    message_placeholder.markdown(full_response + "▌")
            else:
                full_response = "Error receiving response from LLM API"
            message_placeholder.markdown(full_response)
            st.session_state["response"] = full_response
            messages.append(
                    {"role": "assistant", "content": st.session_state["response"], "prompt": prompt}
            )
        if st.session_state.get("run_id"):
            run_id = st.session_state.run_id
            streamlit_feedback(**feedback_kwargs, key=f"feedback_{int(len(messages)/2)}", 
                               kwargs={"run_id": st.session_state.run_id,
                                "prompt": messages[-1]["prompt"],
                                "response": messages[-1]["content"]})
chatbot_app()