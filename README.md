# 🎵 Beat (Phase 2) — WAS ↔ S3 ↔ DB ↔ SQS ↔ AI 비동기 파이프라인

> **사용자 업로드 음악을 AI로 분석**하고, **분석 결과(JSON/MP4)** 를 기반으로 웹 화면이 반응하도록 만드는  
> **하이브리드(AWS + 온프레) 비동기 처리 아키텍처**입니다.

<p align="center">
  <img src="./docs/architecture.png" alt="Architecture" width="820" />
</p>

<p align="center">
  <img alt="AWS" src="https://img.shields.io/badge/AWS-ECS%20%7C%20S3%20%7C%20SQS%20%7C%20ALB-orange" />
  <img alt="FastAPI" src="https://img.shields.io/badge/FastAPI-API%20Server-009688" />
  <img alt="Terraform" src="https://img.shields.io/badge/Terraform-IaC-7B42BC" />
  <img alt="Datadog" src="https://img.shields.io/badge/Datadog-Monitoring-632CA6" />
</p>

---

## 목차

- [1. 프로젝트 한 줄 요약](#1-프로젝트-한-줄-요약)
- [2. 전체 흐름](#2-전체-흐름)
- [3. 구성요소](#3-구성요소)
- [4. API 스펙](#4-api-스펙)
- [5. SQS 메시지 계약](#5-sqs-메시지-계약)
- [6. DB 스키마](#6-db-스키마)
- [7. 환경 변수](#7-환경-변수)
- [8. 로컬 실행](#8-로컬-실행)
- [9. 배포 메모](#9-배포-메모)
- [10. 트러블슈팅](#10-트러블슈팅)
- [11. 다음 개선 과제](#11-다음-개선-과제)
- [Appendix. 리포지토리 구조(예시)](#appendix-리포지토리-구조예시)

---

## 1. 프로젝트 한 줄 요약

- **Web**(정적 페이지)에서 음악 업로드
- **WAS(FastAPI, ECS)** 가 **S3 업로드 + DB jobs 생성 + SQS Job 발행**
- **AI(온프레)** 가 **SQS Job 소비 → 분석 → S3 결과 업로드 → SQS Result 발행**
- **WAS Result Consumer** 가 **SQS Result 소비 → DB jobs 업데이트(DONE/FAIL)**
- **Web**은 `/api/jobs/{id}` & `/api/jobs/{id}/results` 로 **상태/결과 URL(프리사인)** 을 받아 화면을 갱신

---

## 2. 전체 흐름

```mermaid
sequenceDiagram
  autonumber
  participant U as User(Browser)
  participant W as Web(Static)
  participant A as WAS(FastAPI on ECS)
  participant S3 as S3
  participant DB as MySQL(or RDS/Proxy)
  participant J as SQS Job Queue
  participant AI as AI Server(On-Prem)
  participant R as SQS Result Queue

  U->>W: 파일 선택/업로드
  W->>A: POST /api/jobs (multipart)
  A->>S3: uploads/{job_id}/{filename} 업로드
  A->>DB: jobs INSERT (PENDING)
  A->>J: job 메시지 발행
  A->>DB: jobs UPDATE (QUEUED)

  AI->>J: 메시지 수신(consume)
  AI->>S3: results/{job_id}/result.json, video.mp4 업로드
  AI->>R: result 메시지 발행

  A->>R: 메시지 수신(consume)
  A->>DB: jobs UPDATE (DONE/FAIL, result keys)

  W->>A: GET /api/jobs/{job_id}
  alt DONE
    W->>A: GET /api/jobs/{job_id}/results
    A-->>W: presigned urls(json/mp4/audio)
  else QUEUED/PENDING
    W-->>U: 진행중 UI
  end

```
3. 구성요소
구분	컴포넌트	역할
Front	Web(Static)	업로드/폴링/결과 반영(UI)
Backend	WAS(FastAPI)	업로드 수신, S3 저장, DB 기록, SQS 발행, 결과 URL 제공
Queue	SQS Job/Result + DLQ	비동기 처리(분석 요청/결과 전달), 실패 메시지 분리
Storage	S3	원본 업로드 + 결과 산출물(JSON/MP4/HTML 등) 보관
DB	jobs 테이블	작업 상태/결과 키 저장(멱등 업데이트)
AI	온프레 AI 서버	Job consume → 분석 → 결과 업로드 → Result publish
Network	VPC Peering + DB Proxy(EC2+HAProxy)	VPC 분리 환경에서 DB 연결 우회(TCP 프록시)
Observability	Datadog	ALB/ECS/Task 모니터링

✅ 현재 구현은 WAS 내부에 Result Consumer(thread) 를 띄워 결과 큐를 소비합니다. (마감용 빠른 완성 버전)

4. API 스펙
4.1 Health

GET /api/health

{ "ok": true }
4.2 Job 생성 (업로드)

POST /api/jobs (multipart/form-data)

필드:

file (필수): mp3/wav 등

version (선택, 기본 3): AI 계약 버전(1/2/3)

user_request (선택, 기본 ""): 사용자 프롬프트/옵션

응답 예시:

{
  "job_id": "6377193a-b99d-4a09-8a81-d6f89088c833",
  "status": "QUEUED",
  "upload_s3_key": "uploads/6377193a-b99d-4a09-8a81-d6f89088c833/song.mp3"
}
4.3 Job 상태 조회

GET /api/jobs/{job_id}

응답 예시:

{
  "job_id": "...",
  "status": "DONE",
  "upload_s3_key": "uploads/.../song.mp3",
  "original_name": "song.mp3",
  "result_json_key": "results/.../result.json",
  "result_html_key": null,
  "result_mp4_key": "results/.../video.mp4",
  "error": null
}
4.4 결과 URL 조회 (DONE일 때만)

GET /api/jobs/{job_id}/results

조건:

status != DONE 이면 409 Conflict

응답 예시:

{
  "job_id": "...",
  "status": "DONE",
  "urls": {
    "json": "https://...",
    "mp4": "https://...",
    "audio": "https://..."
  }
}
5. SQS 메시지 계약
5.1 Job Queue (WAS → AI)
{
  "task_id": "<job_id>",
  "s3_audio_key": "uploads/<job_id>/<filename>",
  "version": 3,
  "user_request": "default"
}
5.2 Result Queue (AI → WAS)
{
  "task_id": "<job_id>",
  "status": "DONE",
  "result": {
    "json_key": "results/<job_id>/result.json",
    "html_key": null,
    "mp4_key": "results/<job_id>/video.mp4"
  },
  "version": 3,
  "error": null
}

🔎 참고: SNS→SQS 형태로 감싸져 오는 경우를 대비해 {"Message":"...json..."} 형태도 방어적으로 파싱합니다.

6. DB 스키마

현재 DB는 jobs 테이블만 사용합니다.

6.1 jobs 테이블 (권장 DDL 예시)
CREATE TABLE jobs (
  job_id          VARCHAR(36)  NOT NULL PRIMARY KEY,
  upload_s3_key   TEXT         NOT NULL,
  original_name   TEXT         NULL,
  status          VARCHAR(16)  NOT NULL,

  result_json_key TEXT         NULL,
  result_html_key TEXT         NULL,
  result_mp4_key  TEXT         NULL,
  error_message   TEXT         NULL,

  created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE INDEX idx_jobs_status ON jobs(status);
6.2 상태값

PENDING → DB row 생성 직후

QUEUED → SQS job 발행 완료

DONE → 결과 처리 완료(키 저장)

FAIL → 실패(에러 메시지 기록)

✅ SQS(Standard)는 중복 메시지가 올 수 있어 멱등 업데이트(이미 DONE이면 덮어쓰기 방지) 를 적용했습니다.

7. 환경 변수

ECS Task 환경변수(또는 .env)로 주입합니다.
⚠️ 절대 secrets(tfvars, .env)를 Git에 커밋하지 마세요. .env.example만 올리기!

7.1 AWS / S3

AWS_REGION (default: ap-northeast-2)

S3_BUCKET (예: ai-project-result)

S3_UPLOAD_PREFIX (default: uploads)

S3_RESULT_PREFIX (default: results)

PRESIGN_EXPIRE_SECONDS (default: 3600)

7.2 SQS

JOB_QUEUE_URL (필수)

RESULT_QUEUE_URL (필수)

7.3 DB

DB_HOST (필수)

DB_PORT (default: 3306)

DB_USER (필수)

DB_PASS (필수)

DB_NAME (필수)

DB_CHARSET (default: utf8mb4)

7.4 (선택) Callback 테스트용

CALLBACK_TOKEN (기본 change-me)

8. 로컬 실행

로컬에서 전체 파이프라인을 완전히 재현하려면 AWS 리소스(S3/SQS)와 DB가 필요합니다.

python -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt

cp .env.example .env
# .env에 JOB/RESULT_QUEUE_URL, DB_* 등 설정

uvicorn app.main:app --host 0.0.0.0 --port 8080
8.1 빠른 테스트(curl)
# 업로드
curl -X POST "http://localhost:8080/api/jobs" \
  -F "file=@./song.mp3" \
  -F "version=3" \
  -F "user_request="

# 상태 조회
curl "http://localhost:8080/api/jobs/<job_id>"

# DONE이면 결과 URL
curl "http://localhost:8080/api/jobs/<job_id>/results"
9. 배포 메모
9.1 ECS(Fargate)

WAS는 ECS Task로 배포

startup에서 Result Consumer(thread) 가 실행되어 Result Queue를 소비

9.2 IAM 권한 체크리스트

Task Role(또는 Execution Role)에 아래 권한 필요:

S3: PutObject, GetObject

SQS:

Job Queue: SendMessage

Result Queue: ReceiveMessage, DeleteMessage, GetQueueAttributes

9.3 네트워크(하이브리드 / DB Proxy)

VPC 분리/라우팅 때문에 DB 직접 연결이 어려워 DR VPC의 EC2를 DB Proxy로 사용

EC2에서 HAProxy TCP 프록시:

0.0.0.0:3308 listen → 실제 DB :3306

10. 트러블슈팅
<details> <summary><b>① HAProxy가 기동 실패</b></summary>

frontend default_backend ↔ backend 이름 불일치 → 즉시 실패

포트 충돌(3307 사용 중 등) → 3308로 변경

sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl status haproxy
sudo ss -lntp | grep 3308
</details> <details> <summary><b>② WAS → DB 연결 500 / timeout</b></summary>

VPC/라우팅/SG 문제 가능

Task Definition env가 반영 안 되면 새 revision + Force new deployment

</details> <details> <summary><b>③ MySQL 인증 플러그인 오류(cryptography)</b></summary>

sha256_password / caching_sha2_password 사용 시 cryptography 필요

requirements.txt 추가 후 이미지 재빌드/재배포

</details> <details> <summary><b>④ SQS AccessDenied</b></summary>

Task Role 정책에 SQS 권한 누락 (특히 ResultQueue Receive/Delete)

</details> <details> <summary><b>⑤ Web이 DONE 이후에도 화면 변경 안 됨</b></summary>

응답 스키마 불일치(키 이름/중첩 구조) 원인이 많음

권장 흐름: DONE → /results 호출 → urls(mp4/json/audio) 사용

</details> <details> <summary><b>⑥ DB host blocked(1129)</b></summary>
mysqladmin -u root -p flush-hosts

연결 폭주/재시도 줄이기(consumer 재시도, desired_count 조정)

</details>
