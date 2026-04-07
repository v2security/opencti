FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends git libmagic1 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/connector

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ src/
COPY config.yml config.yml

WORKDIR /opt/connector/src

ENTRYPOINT ["python", "__main__.py"]
