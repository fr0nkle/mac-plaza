FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    PLAZA_BIND=0.0.0.0 PORT=8787 PLAZA_DATABASE=/data/plaza.sqlite3 \
    PLAZA_UPDATES=/data/updates PLAZA_DOWNLOADS=/data/downloads
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && mkdir /data && chown 10001:10001 /data
COPY server.py presence_bot.py updates.py downloads.py public_releases.py ./
USER 10001:10001
VOLUME /data
EXPOSE 8787
HEALTHCHECK --interval=60s --timeout=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8787/health', timeout=3)"
CMD ["python", "server.py"]
