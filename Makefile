# 常用指令集中在這裡，降低「漏打一個參數」的人為錯誤
REGION ?= ap-southeast-2
TF     ?= terraform

.PHONY: test run docker-build docker-run bootstrap ci-secrets push-initial infra-up outputs infra-down destroy-all

## ---- 本機開發 ----
test:
	pytest -v

run:
	uvicorn app.main:app --reload --port 8000

docker-build:
	docker build -t orders-api:local .

docker-run: docker-build
	docker run --rm -p 8000:8000 orders-api:local

## ---- 雲端環境（依序執行） ----
# 1) 預算告警、state bucket、ECR、GitHub OIDC role
bootstrap:
	cd infra/bootstrap && $(TF) init && $(TF) apply
	cd infra/bootstrap && $(TF) output -raw backend_hcl > ../app/backend.hcl
	@echo "→ 下一步：把 CI 憑證設到 GitHub Secrets（指令見 make ci-secrets）"

# 把 CI 憑證直接寫進 GitHub Secrets（需先安裝並登入 gh CLI），secret 不經過畫面與剪貼簿
ci-secrets:
	@MODE=$$(cd infra/bootstrap && $(TF) output -raw github_deploy_role_arn 2>/dev/null | grep -q '^arn:' && echo oidc || echo access_key); \
	if [ "$$MODE" = "oidc" ]; then \
	  cd infra/bootstrap && $(TF) output -raw github_deploy_role_arn | gh secret set AWS_DEPLOY_ROLE_ARN && gh variable set AWS_AUTH_MODE --body oidc; \
	else \
	  cd infra/bootstrap && $(TF) output -raw ci_access_key_id | gh secret set AWS_ACCESS_KEY_ID && \
	  $(TF) output -raw ci_secret_access_key | gh secret set AWS_SECRET_ACCESS_KEY; \
	fi; echo "GitHub secrets 已設定（模式：$$MODE）"

# 2) 推第一個映像到 ECR（ECS service 建立時需要一個存在的映像）
push-initial:
	scripts/manual_deploy.sh --push-only

# 3) 建 VPC / ALB / ECS / 監控；IMAGE_TAG 用上一步印出的 tag
infra-up:
	@test -n "$(IMAGE_TAG)" || (echo "用法：make infra-up IMAGE_TAG=<tag>"; exit 1)
	cd infra/app && $(TF) init -backend-config=backend.hcl && $(TF) apply -var image_tag=$(IMAGE_TAG)

outputs:
	cd infra/app && $(TF) output

## ---- 拆除（先 app 再 bootstrap，因為 app 的 state 存在 bootstrap 建的 bucket） ----
infra-down:
	cd infra/app && $(TF) destroy -var image_tag=unused

destroy-all: infra-down
	cd infra/bootstrap && $(TF) destroy
