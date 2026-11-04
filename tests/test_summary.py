"""彙總邏輯的「規則書」。

每個測試守護一條規則。以後有人改了 app/summary.py，只要破壞其中任何一條，
這裡就會變紅，GitHub Actions 的 test 失敗，deploy 不會執行，錯的程式上不了線。
"""

import pytest

from app.summary import OrdersFileError, load_and_summarize, summarize


def rows(*pairs):
    """測試小工具：rows(("A", "2"), ("B", "5")) → 模擬 CSV 讀進來的資料列。"""
    return [{"product": p, "quantity": q} for p, q in pairs]


# ---------------------------------------------------------------------------
# 規則 1：同一個商品要「加總」，不是覆蓋
# ---------------------------------------------------------------------------
def test_summarize_aggregates_by_product():
    assert summarize(rows(("A", "2"), ("B", "5"), ("A", "3"))) == {"A": 5, "B": 5}


def test_same_product_many_times_is_summed():
    # 同一商品出現 4 次：1+2+3+4 = 10。若有人把 += 改成 =，只會剩最後一筆 4
    assert summarize(rows(("A", "1"), ("A", "2"), ("A", "3"), ("A", "4"))) == {"A": 10}


def test_total_is_preserved():
    # 加總前後總量要一致：不能多算也不能漏算
    data = rows(("A", "3"), ("B", "7"), ("A", "5"), ("C", "1"))
    assert sum(summarize(data).values()) == 3 + 7 + 5 + 1


# ---------------------------------------------------------------------------
# 規則 2：輸出依商品名稱排序（下游報表依賴固定順序）
# ---------------------------------------------------------------------------
def test_output_sorted_by_product_name():
    result = summarize(rows(("Webcam", "1"), ("Keyboard", "1"), ("Mouse", "1")))
    assert list(result) == ["Keyboard", "Mouse", "Webcam"]


# ---------------------------------------------------------------------------
# 規則 3：數量必須是 >= 0 的整數，否則明確報錯（不可默默算錯）
# ---------------------------------------------------------------------------
def test_zero_quantity_is_allowed():
    assert summarize(rows(("A", "0"))) == {"A": 0}


@pytest.mark.parametrize(
    "bad_qty",
    ["two", "1.5", "", "   ", "-1", "-100"],
    ids=["text", "decimal", "empty", "spaces", "minus1", "minus100"],
)
def test_summarize_rejects_bad_quantity(bad_qty):
    with pytest.raises(OrdersFileError):
        summarize(rows(("A", bad_qty)))


def test_error_message_points_to_the_csv_line():
    # 第 1 行是標題，所以第 2 筆資料 = CSV 第 3 行；錯誤訊息要讓人一眼找到哪一行
    with pytest.raises(OrdersFileError, match="line 3"):
        summarize(rows(("A", "1"), ("B", "oops")))


# ---------------------------------------------------------------------------
# 規則 4：商品名稱不可空白；前後空格要去掉
# ---------------------------------------------------------------------------
@pytest.mark.parametrize("bad_product", ["", "   "], ids=["empty", "spaces"])
def test_empty_product_is_rejected(bad_product):
    with pytest.raises(OrdersFileError, match="product is empty"):
        summarize(rows((bad_product, "1")))


def test_whitespace_is_trimmed():
    # " Mouse " 和 "Mouse" 是同一個商品；" 3 " 是 3
    assert summarize(rows((" Mouse ", " 3 "), ("Mouse", "2"))) == {"Mouse": 5}


def test_product_name_is_case_sensitive():
    # 目前的約定：大小寫視為不同商品。若要改規則，必須連同這個測試一起改（＝有意識的決定）
    assert summarize(rows(("mouse", "1"), ("Mouse", "1"))) == {"Mouse": 1, "mouse": 1}


# ---------------------------------------------------------------------------
# 規則 5：讀檔層的檢查
# ---------------------------------------------------------------------------
def test_empty_input_returns_empty_dict():
    assert summarize([]) == {}


def test_header_only_csv_returns_empty_dict(tmp_path):
    f = tmp_path / "empty.csv"
    f.write_text("order_id,order_date,product,quantity\n", encoding="utf-8")
    assert load_and_summarize(f) == {}


@pytest.mark.parametrize(
    "header",
    ["order_id,product", "order_id,quantity", "order_id,order_date"],
    ids=["no-quantity", "no-product", "no-both"],
)
def test_missing_column(tmp_path, header):
    f = tmp_path / "bad.csv"
    f.write_text(f"{header}\nORD-1,X\n", encoding="utf-8")
    with pytest.raises(OrdersFileError, match="missing columns"):
        load_and_summarize(f)


def test_extra_columns_are_ignored(tmp_path):
    # 多了不相干的欄位（例如 price）不影響結果
    f = tmp_path / "extra.csv"
    f.write_text("order_id,product,quantity,price\n1,A,2,99\n2,A,3,10\n", encoding="utf-8")
    assert load_and_summarize(f) == {"A": 5}
