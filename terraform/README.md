## Terraform 실행 방법 (초보자 가이드)

### 1️⃣ 환경 설정 파일 준비
```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars

2️⃣ terraform.tfvars 수정
AWS Region
VPC CIDR
Subnet CIDR
프로젝트 이름

3️⃣ Terraform 초기화
terraform init

4️⃣ 실행 계획 확인
terraform plan

5️⃣ 리소스 생성
terraform apply

6️⃣ 리소스 삭제
terraform destroy
