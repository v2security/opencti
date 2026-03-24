FROM python:3.12-slim

WORKDIR /opt/connector

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ src/
COPY config.yml.sample config.yml.sample

WORKDIR /opt/connector/src

ENTRYPOINT ["python", "__main__.py"]
