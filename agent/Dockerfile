FROM python:3.13-slim

WORKDIR /app

# Install dependencies first so this layer caches between builds.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py app.py ./

# Cloud Run injects PORT; Streamlit must bind to it and to 0.0.0.0 or the
# container will fail its health check. Shell form so $PORT is expanded.
ENV PORT=8080
EXPOSE 8080

CMD streamlit run app.py \
    --server.port=$PORT \
    --server.address=0.0.0.0 \
    --server.headless=true \
    --browser.gatherUsageStats=false