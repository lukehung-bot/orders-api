"""訂單彙總邏輯：與 Web 框架無關，方便單元測試。"""

import csv
from collections.abc import Iterable, Mapping
from pathlib import Path

REQUIRED_COLUMNS = {"product", "quantity"}


class OrdersFileError(ValueError):
    """orders.csv 格式錯誤（缺欄位、數量非整數或為負數）。"""


def summarize(rows: Iterable[Mapping[str, str]]) -> dict[str, int]:
    """回傳每個商品的總數量，依商品名稱排序。"""
    totals: dict[str, int] = {}
    for line_no, row in enumerate(rows, start=2):  # 第 1 行是 header
        product = (row.get("product") or "").strip()
        raw_qty = (row.get("quantity") or "").strip()
        if not product:
            raise OrdersFileError(f"line {line_no}: product is empty")
        try:
            qty = int(raw_qty)
        except ValueError as exc:
            raise OrdersFileError(f"line {line_no}: quantity {raw_qty!r} is not an integer") from exc
        if qty < 0:
            raise OrdersFileError(f"line {line_no}: quantity must be >= 0")
        totals[product] = totals.get(product, 0) + qty
    return dict(sorted(totals.items()))


def load_and_summarize(path: Path) -> dict[str, int]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        missing = REQUIRED_COLUMNS - set(reader.fieldnames or [])
        if missing:
            raise OrdersFileError(f"missing columns: {sorted(missing)}")
        return summarize(reader)
