FROM continuumio/anaconda3 as base
RUN apt-get -qq update
RUN apt-get install -y wget adduser libfontconfig1 musl
COPY entrypoint.sh grafana.ini ./
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]