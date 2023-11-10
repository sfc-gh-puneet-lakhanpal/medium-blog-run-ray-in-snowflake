FROM nvcr.io/nvidia/pytorch:23.06-py3
RUN apt-get update -y
RUN pip3 install --upgrade pip
COPY ray_requirements.txt usecase_requirements.txt ./
RUN pip3 install -r ray_requirements.txt
RUN pip3 install -r usecase_requirements.txt
ENV PYTHONUNBUFFERED=1
COPY deployapi /deployapi
WORKDIR /deployapi