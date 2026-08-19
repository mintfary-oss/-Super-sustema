FROM python:3.12-slim

WORKDIR /app

# Утилиты: lspci (для поиска GPU в PCIe), curl (для healthcheck)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends pciutils curl && \
    rm -rf /var/lib/apt/lists/*

# Зависимости Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Код и шаблоны
COPY app.py .
COPY templates/ templates/

# Директория для shared файлов (bind-mounted с хоста через docker-compose)
RUN mkdir -p /shared

EXPOSE 8765

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8765", "--log-level", "warning"]
