FROM continuumio/anaconda3 as base
RUN apt-get -qq update
RUN apt-get install -y wget
COPY entrypoint.sh prometheus.yml ./
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]