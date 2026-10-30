import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.summary import OrdersFileError, load_and_summarize, summarize

client = TestClient(app)


def test_summarize_aggregates_by_product():
    rows = [
        {"product": "A", "quantity": "2"},
        {"product": "B", "quantity": "5"},
        {"product": "A", "quantity": "3"},
    ]
    assert summarize(rows) == {"A": 5, "B": 5}


def test_summarize_rejects_bad_quantity():
    with pytest.raises(OrdersFileError):
        summarize([{"product": "A", "quantity": "two"}])


def test_missing_column(tmp_path):
    f = tmp_path / "bad.csv"
    f.write_text("order_id,product\n1,A\n", encoding="utf-8")
    with pytest.raises(OrdersFileError):
        load_and_summarize(f)


def test_summary_endpoint_matches_repo_csv():
    # 期望值由 data/orders.csv 人工核對：20 列、總量 108
    resp = client.get("/summary")
    assert resp.status_code == 200
    totals = resp.json()["total_quantity_by_product"]
    assert totals == {"Keyboard": 44, "Monitor": 12, "Mouse": 27, "USB-C Cable": 15, "Webcam": 10}
    assert sum(totals.values()) == 108


def test_healthz():
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
