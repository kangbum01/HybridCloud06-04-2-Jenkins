###############################
# 이 코드는 was를 도커이미지로 빌드 후 was용 ecr에 올리는 자동 스크립트 입니다.
# 사용법
# 1. 해당 파일을 Dockerfile위치에 놓습니다
# 2. chmod +x ./push_was.sh , sudo useradd -aG docker 사용자 
# 3. ./push_was.sh 를 통해 이미지 업로드
# * 해당 이미지는 new-was, 사용자 지정 태그 2개가 올라갑니다
# * ECS는 new-was 태그를 가진 이미지를 가져오도록 설정되어 있습니다.
###############################
#!/usr/bin/env bash
set -euo pipefail

# ====== 수정할 값 2개 ======
AWS_REGION="ap-northeast-2"
ECR_REPO_NAME="beat-dev-was"     # <-- 너가 만든 WAS ECR 리포 이름
DATE_TAG="v.$(date +%y%m%d)"     # <-- 원하는 태그 (날짜/커밋sha 추천)
TAG2="new-was"
# TAG3="latest"                  # 필요하면 추가하세요
# ===========================

# (선택) M1/M2면 amd64로 빌드 권장 (ECS Fargate x86 기준)
PLATFORM="linux/amd64"

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

IMAGE_DATE="${ECR_REGISTRY}/${ECR_REPO_NAME}:${DATE_TAG}"
IMAGE_NEW="${ECR_REGISTRY}/${ECR_REPO_NAME}:${TAG2}"

echo "[1/4] ECR Login..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "[2/4] Docker Build (tag: ${DATE_TAG})..."
# Dockerfile 있는 디렉토리(=requirements.txt, app/ 있는 곳)에서 실행해야 함
docker buildx build --platform "${PLATFORM}" -t "${IMAGE_DATE}" --load .

echo "[3/4] Tagging..."
docker tag "${IMAGE_DATE}" "${IMAGE_NEW}"

echo "[4/4] Done!"
docker push "${IMAGE_DATE}"
docker push "${IMAGE_NEW}"

echo "Done!"
echo "Pushed:"
echo "- ${IMAGE_DATE}"
echo "- ${IMAGE_NEW}"