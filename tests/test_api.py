"""API 對外的「約定」。

其他系統（報表、前端、監控）依賴這些網址與欄位名稱。
有人改了欄位名稱或回傳格式，這裡會先擋下來，而不是等使用者發現壞掉。
"""

import pytest
from fastapi.testclient import TestClient

import app.main as main
from app.main import app

client = TestClient(app)

# 由 data/orders.csv 人工逐筆核對的正確答案：20 筆、總量 108
EXPECTED = {"Keyboard": 44, "Monitor": 12, "Mouse": 27, "USB-C Cable": 15, "Webcam": 10}


def test_summary_endpoint_matches_repo_csv():
    resp = client.get("/summary")
    assert resp.status_code == 200
    totals = resp.json()["total_quantity_by_product"]
    assert totals == EXPECTED
    assert sum(totals.values()) == 108


@pytest.mark.parametrize("product,qty", list(EXPECTED.items()))
def test_each_product_total(product, qty):
    # 拆成每個商品一個測試：失敗時直接看出是哪個商品算錯
    assert client.get("/summary").json()["total_quantity_by_product"][product] == qty


def test_summary_response_shape_is_stable():
    # 回傳格式是對外約定：外層只有一個 key，值是「商品 → 整數」
    body = client.get("/summary").json()
    assert list(body) == ["total_quantity_by_product"]
    assert all(isinstance(k, str) and isinstance(v, int) for k, v in body["total_quantity_by_product"].items())


def test_summary_reads_the_configured_file(tmp_path, monkeypatch):
    # 換一份資料，結果跟著變 → 證明真的有讀檔，不是把答案寫死在程式裡
    f = tmp_path / "orders.csv"
    f.write_text("order_id,product,quantity\n1,Pen,2\n2,Pen,3\n3,Ink,1\n", encoding="utf-8")
    monkeypatch.setattr(main, "ORDERS_CSV", f)
    assert client.get("/summary").json() == {"total_quantity_by_product": {"Ink": 1, "Pen": 5}}


def test_bad_csv_returns_500_not_wrong_numbers(tmp_path, monkeypatch):
    # 資料壞了寧可回錯誤（觸發 5xx 告警），也不要回一個看起來正常但算錯的數字
    f = tmp_path / "orders.csv"
    f.write_text("order_id,product,quantity\n1,Pen,-5\n", encoding="utf-8")
    monkeypatch.setattr(main, "ORDERS_CSV", f)
    resp = TestClient(app, raise_server_exceptions=False).get("/summary")
    assert resp.status_code == 500


def test_healthz():
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_healthz_reports_version(monkeypatch):
    # 線上用 /healthz 的 version 確認跑的是哪一版（CI 會帶入 git commit 編號）
    monkeypatch.setattr(main, "APP_VERSION", "abc1234")
    assert client.get("/healthz").json() == {"status": "ok", "version": "abc1234"}


def test_unknown_path_is_404():
    assert client.get("/does-not-exist").status_code == 404
