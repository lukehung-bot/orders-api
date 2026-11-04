#!/usr/bin/env bash
# DEMO 用：故意把程式改壞，示範單元測試會把錯誤擋下來。
#
# 用法：
#   scripts/break.sh list        # 列出可以示範的「改壞方式」
#   scripts/break.sh 1           # 套用第 1 種改壞方式（之後跑 pytest 會失敗）
#   scripts/break.sh restore     # 還原（等同 git checkout app/）
set -euo pipefail
cd "$(dirname "$0")/.."

declare -A FILE OLD NEW DESC
FILE[1]=app/summary.py; OLD[1]='totals[product] = totals.get(product, 0) + qty'; NEW[1]='totals[product] = qty'
DESC[1]='加總變覆蓋：同一商品只留最後一筆（最常見的手滑）'
FILE[2]=app/summary.py; OLD[2]='if qty < 0:'; NEW[2]='if False:'
DESC[2]='拿掉負數檢查：退貨 -5 被默默算進總量'
FILE[3]=app/summary.py; OLD[3]='qty = int(raw_qty)'; NEW[3]='qty = int(float(raw_qty))'
DESC[3]='「好心」接受小數：1.5 被悄悄變成 1'
FILE[4]=app/summary.py; OLD[4]='return dict(sorted(totals.items()))'; NEW[4]='return totals'
DESC[4]='拿掉排序：輸出順序不固定，下游報表對不上'
FILE[5]=app/main.py; OLD[5]='{"total_quantity_by_product": totals}'; NEW[5]='{"totals": totals}'
DESC[5]='改了回傳欄位名稱：所有呼叫這支 API 的系統都會壞'
FILE[6]=app/summary.py; OLD[6]='product = (row.get("product") or "").strip()'; NEW[6]='product = (row.get("product") or "").strip().title()'
DESC[6]='「順手」統一大小寫：USB-C Cable 變成 Usb-C Cable'

case "${1:-list}" in
  list)
    for i in 1 2 3 4 5 6; do printf '  %s) %s\n' "$i" "${DESC[$i]}"; done ;;
  restore)
    git checkout -- app/ && echo "已還原 app/" ;;
  [1-6])
    i=$1
    python3 - "${FILE[$i]}" "${OLD[$i]}" "${NEW[$i]}" <<'PY'
import sys, pathlib
path, old, new = sys.argv[1:]
p = pathlib.Path(path); s = p.read_text(encoding="utf-8")
if old not in s:
    sys.exit(f"找不到要改的程式碼（是否已經改過？先執行 scripts/break.sh restore）：{old}")
p.write_text(s.replace(old, new, 1), encoding="utf-8")
PY
    echo "已套用 #$i：${DESC[$i]}"
    echo "改了 ${FILE[$i]}："
    echo "  - ${OLD[$i]}"
    echo "  + ${NEW[$i]}"
    echo "→ 現在執行 pytest 看看" ;;
  *) echo "用法：$0 list | 1-6 | restore"; exit 1 ;;
esac
