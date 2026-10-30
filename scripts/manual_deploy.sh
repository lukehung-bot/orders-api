#!/usr/bin/env bash
# 手動部署（第二部分 F 用）：本機 build → 推 ECR → 註冊新 task definition → 更新 ECS service
# 每一步都計時，方便和 pipeline 比較。
#
# 用法：
#   scripts/manual_deploy.sh            # 完整手動部署
#   scripts/manual_deploy.sh --push-only # 只 build + push（首次建環境前，先讓 ECR 有映像）
#
# 需求：aws CLI ≥ 2.32（已登入：免費方案用 aws login + AWS_PROFILE=orders；付費方案可用 aws sso login）、docker、jq
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"
PROJECT="${PROJECT:-orders-api}"
CLUSTER="${PROJECT}-cluster"
SERVICE="${PROJECT}-svc"
CONTAINER="app"
TAG="${TAG:-manual-$(git rev-parse --short HEAD)-$(date +%H%M%S)}" # ECR 為 IMMUTABLE，tag 不可重複

START=$(date +%s); LAST=$START
step() { local now; now=$(date +%s); printf '  [%3ds] %s\n' "$((now - LAST))" "$1"; LAST=$now; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${PROJECT}:${TAG}"
echo "Deploying ${TAG}"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
step "ECR login"

# Fargate 跑 x86_64；Apple Silicon 不加 --platform 會 build 出 arm64 映像，任務會起不來（常見錯誤）
docker build --platform linux/amd64 --build-arg APP_VERSION="$TAG" -t "$IMAGE" .
step "docker build"

docker push "$IMAGE" >/dev/null
step "docker push"

if [[ "${1:-}" == "--push-only" ]]; then
  echo "Pushed ${IMAGE}"
  echo "IMAGE_TAG=${TAG}"
  exit 0
fi

aws ecs describe-task-definition --task-definition "$PROJECT" --region "$REGION" --query taskDefinition \
  | jq --arg img "$IMAGE" --arg ver "$TAG" --arg c "$CONTAINER" '
      .containerDefinitions |= map(if .name == $c then
          .image = $img
          | .environment = ([.environment[]? | select(.name != "APP_VERSION")] + [{name:"APP_VERSION", value:$ver}])
        else . end)
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' \
  > taskdef.manual.json
NEW_TD=$(aws ecs register-task-definition --region "$REGION" --cli-input-json file://taskdef.manual.json \
  --query taskDefinition.taskDefinitionArn --output text)
rm -f taskdef.manual.json
step "register task definition -> ${NEW_TD##*/}"

aws ecs update-service --region "$REGION" --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$NEW_TD" >/dev/null
step "update-service"

aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE"
step "wait services-stable"

echo "Total: $(( $(date +%s) - START ))s"
