FROM nvidia/cuda:11.8.0-devel-ubuntu22.04
RUN apt-get update -y
RUN apt-get install -y python3-pip git
COPY ray_requirements.txt ./
RUN pip3 install -r ray_requirements.txt
COPY usecase_requirements.txt entrypoint.sh ./
RUN chmod +x entrypoint.sh
RUN pip3 install -r usecase_requirements.txt
RUN pip3 install --force --no-deps git+https://github.com/UKPLab/sentence-transformers.git
ENTRYPOINT ["./entrypoint.sh"]