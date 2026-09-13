FROM python:3.12-slim

RUN useradd --create-home --uid 1000 bridge

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

RUN mkdir -p /logs && chown -R bridge:bridge /app /logs

USER bridge

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=3).status == 200 else 1)"

CMD ["python", "-m", "app.server"]
