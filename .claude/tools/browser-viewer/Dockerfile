FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir aiohttp==3.* websockets==13.*
COPY viewer.py index.html ./
EXPOSE 6080
CMD ["python3", "viewer.py"]
