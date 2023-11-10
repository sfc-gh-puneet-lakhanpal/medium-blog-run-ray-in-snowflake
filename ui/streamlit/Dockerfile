FROM python:3.10

WORKDIR /app
ADD ./requirements.txt /app/
RUN pip install --upgrade pip
# fix for oscrypto issue
RUN pip install oscrypto@git+https://github.com/wbond/oscrypto.git@d5f3437ed24257895ae1edd9e503cfb352e635a8
RUN pip install -r requirements.txt

ADD ./ /app

EXPOSE 8501

ENV STREAMLIT_GLOBAL_DISABLE_WATCHDOG_WARNING=1
CMD ["streamlit", "run", "LLM_Chat.py"]