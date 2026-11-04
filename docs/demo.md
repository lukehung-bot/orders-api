# DEMO 手冊：改錯程式會被擋下

兩段示範：
1. 本機 VS Code：故意改壞程式 → 單元測試變紅。
2. GitHub Actions：把壞程式推上 main → `test` 失敗 → `deploy` 被跳過 → 線上版本不變。

測試共 34 項，分兩個檔案：

| 檔案 | 守護什麼 |
|---|---|
| `tests/test_summary.py` | 彙總規則：同商品加總、輸出排序、數量必須是 ≥ 0 的整數、商品名稱不可空白、前後空格去掉、大小寫有區分、缺欄位會報錯 |
| `tests/test_api.py` | 對外約定：`/summary` 的答案（總量 108）、回傳欄位名稱、真的有讀檔、資料壞了回 500 而不是錯的數字、`/healthz` 回報版本 |

---

## 一、本機（VS Code）

### 事前準備（一次）

```bash
cd ~/orders-api
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q                      # 應該是 34 passed
```

VS Code 的「測試」面板（左側燒杯圖示）：選 **Configure Python Tests → pytest → tests**，就能看到每一項測試，用綠勾和紅叉顯示結果。

### 示範流程（約 3 分鐘）

```bash
pytest -q                      # 1. 起點：全綠
scripts/break.sh list          # 2. 列出 6 種改壞的方式
scripts/break.sh 1             # 3. 套用第 1 種：把「加總」改成「覆蓋」
git diff                       #    給大家看只改了一行
pytest -q                      # 4. 變紅：11 項失敗，訊息顯示期望 44、實際 6
scripts/break.sh restore       # 5. 還原
pytest -q                      #    全綠
```

`scripts/break.sh` 改壞的方式和預期結果（皆已實測）：

| # | 「手滑」 | 情境 | 失敗數 |
|---|---|---|---|
| 1 | `+=` 寫成 `=` | 同一個商品只剩最後一筆 | 11 |
| 2 | 拿掉負數檢查 | 退貨 -5 被默默算進總量 | 3 |
| 3 | `int()` 改成 `int(float())` | 「好心」接受小數，1.5 被悄悄變成 1 | 1 |
| 4 | 拿掉排序 | 輸出順序不固定，下游報表對不上 | 1 |
| 5 | 回傳欄位改名 | 所有呼叫這支 API 的系統都會壞 | 8 |
| 6 | 商品名稱 `.title()` | `USB-C Cable` 變成 `Usb-C Cable` | 3 |

建議示範 **#1**（最直觀，數字明顯不對）和 **#3**（看起來是「改善」，其實偷偷改了規則；只有 1 項測試抓到它，這正是寫測試的價值）。

> 也可以直接在 VS Code 裡手改 `app/summary.py` 那一行，存檔後在測試面板按 ▶，效果一樣、更有臨場感。

---

## 二、GitHub Actions：壞程式上不了線

### 事前（簡報前一天）

1. 先把這次新增的測試推上去，讓 pipeline 跑一次全綠，線上版本＝最新 commit：
   ```bash
   git add tests scripts docs && git commit -m "Add regression tests and demo script" && git push
   gh run watch "$(gh run list -L1 --json databaseId -q '.[0].databaseId')"
   ```
2. 確認 main 沒有開 branch protection 擋直接 push（或改用下方的 PR 版本）。

### 現場（約 8 分鐘，其中 test 只要 ~15 秒就會失敗）

```bash
curl -s $ALB/healthz; echo          # 1. 記下目前的 version（= 上一個 commit）
scripts/break.sh 1                  # 2. 改壞
git commit -am "demo: 加總邏輯被改壞" && git push
gh run watch "$(gh run list -L1 --json databaseId -q '.[0].databaseId')"
#   3. test ✗（約 15 秒）、infra-lint ✓、deploy ⊘ skipped
curl -s $ALB/healthz; echo          # 4. version 完全沒變 → 線上沒受影響
curl -s $ALB/summary; echo          #    數字仍是正確的 Keyboard 44
git revert --no-edit HEAD && git push   # 5. 修正：再跑一次就恢復全綠並正常上線（約 6 分鐘）
```

GitHub 網頁上要給大家看的位置：**Actions → 該次 run**，圖上 `test` 是紅叉、`deploy` 是灰色 skipped；點進 `test` → `pytest -v` 可以看到哪一條規則被破壞。

**PR 版本（更貼近正式流程，也不會動到 main）**：

```bash
git switch -c demo/broken && scripts/break.sh 1
git commit -am "demo: 加總邏輯被改壞" && git push -u origin demo/broken
gh pr create --fill
```

PR 頁面會顯示檢查失敗；開啟 branch protection（要求 `test` 通過）的話，Merge 按鈕會被鎖住。PR 本來就只跑測試、不部署。

---

## 三、環境開關與費用

```bash
aws login --profile orders-login --remote && export AWS_PROFILE=orders   # 12 小時有效
curl -s https://checkip.amazonaws.com                                    # 場地 IP 不同時，更新 infra/app/terraform.tfvars 的 allowed_cidrs
make infra-up IMAGE_TAG=manual-1e026d1-212137                            # 約 5 分鐘；ALB 網址每次重建都會變
export ALB=$(cd infra/app && terraform output -raw alb_url)
gh workflow run ci-cd                                                    # 讓線上版本 = main 最新 commit
```

- 開著的時候約 **0.12 美元／小時**（NAT Gateway、ALB、3 個公網 IPv4、Fargate 0.25 vCPU / 0.5 GB）。
- 示範完：`make infra-down`。繳交前：`make destroy-all`，並刪除 GitHub Secrets。
- 重建後 SNS 會再寄一次訂閱確認信，要點確認，告警信才收得到。
