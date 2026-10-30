# 基底映像取自 ECR Public（Docker Hub 官方映像的鏡像），避免 Docker Hub 匿名拉取的 rate limit
# ---- build stage：安裝相依套件到獨立目錄，最終映像不含 pip cache / build 工具 ----
FROM public.ecr.aws/docker/library/python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- runtime stage ----
FROM public.ecr.aws/docker/library/python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ORDERS_CSV=/app/data/orders.csv
WORKDIR /app
COPY --from=build /install /usr/local
COPY app/ ./app/
COPY data/ ./data/

# 以非 root 身分執行（最小權限）
RUN useradd --uid 10001 --no-create-home appuser
USER 10001

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

EXPOSE 8000
# 容器層級健康檢查（不依賴 curl，slim 映像沒有 curl）
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
