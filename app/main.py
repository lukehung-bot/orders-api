import logging
import os
from pathlib import Path

from fastapi import FastAPI

from app.summary import load_and_summarize

ORDERS_CSV = Path(os.getenv("ORDERS_CSV", Path(__file__).resolve().parent.parent / "data" / "orders.csv"))
APP_VERSION = os.getenv("APP_VERSION", "dev")  # CI 會帶入 git commit SHA，方便確認線上跑的是哪一版

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("orders-api")

app = FastAPI(title="orders-api", version=APP_VERSION)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "version": APP_VERSION}


@app.get("/summary")
def summary() -> dict:
    totals = load_and_summarize(ORDERS_CSV)
    logger.info("summary computed products=%d total_quantity=%d", len(totals), sum(totals.values()))
    return {"total_quantity_by_product": totals}
