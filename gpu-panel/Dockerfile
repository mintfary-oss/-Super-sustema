FROM python:3.12-slim

WORKDIR /app

# Зависимости
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Код и шаблоны
COPY app.py .
COPY templates/ templates/

# Создать папку для shared файлов
RUN mkdir -p /shared

EXPOSE 8765

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8765", "--log-level", "warning"]
