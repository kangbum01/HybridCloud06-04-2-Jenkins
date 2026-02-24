Beat Dev WAS + SQS 비동기 분석 파이프라인 정리
목표

사용자가 업로드한 음악(mp3 등)을 S3에 저장

DB에 작업(job) 메타데이터(업로드 위치, 상태)를 기록

SQS(Job Queue)를 통해 온프레미스 AI 서버에 “분석 요청” 전달

AI 분석 완료 시 SQS(Result Queue)로 결과 메시지를 전달

WAS(또는 Result Worker)가 DB 상태를 DONE/FAIL로 갱신

Web은 /api/jobs/{job_id}로 상태 확인 후 /api/jobs/{job_id}/results에서 presigned URL로 결과 다운로드

전체 아키텍처 흐름

Client → WAS: POST /api/jobs 파일 업로드

WAS → S3: uploads/{job_id}/{filename}로 업로드

WAS → DB

s3_objects에 업로드 객체 기록(운영/감사용)

jobs에 작업 row 생성(status=PENDING)

WAS → SQS(Job Queue): 분석 요청 메시지 발행 → status=QUEUED로 변경

On-Prem AI Worker

Job Queue 수신(long polling)

S3에서 파일 다운로드 → 분석 → 결과를 S3에 업로드(results/...)

**SQS(Result Queue)**로 결과 메시지 발행

Result Worker(WAS 측 권장)

Result Queue 수신

DB jobs 업데이트(status=DONE/FAIL + 결과 키 저장)

Client/Web

GET /api/jobs/{job_id}로 상태 확인

DONE이면 GET /api/jobs/{job_id}/results에서 presigned URL 제공

SQS 구성
Queues

beat-dev-job-queue : WAS → AI 분석 요청

beat-dev-result-queue : AI → WAS 결과 전달

*-dlq : 실패 메시지 격리(Dead Letter Queue)

DLQ(Dead Letter Queue) 역할

메시지가 처리 실패로 maxReceiveCount를 초과하면 DLQ로 이동

무한 재시도 방지 + 장애 메시지 분석 가능

메시지 포맷(권장)
Job Queue 메시지
{
  "v": 1,
  "type": "JOB_REQUEST",
  "job_id": "uuid",
  "bucket": "ai-project-result",
  "object_key": "uploads/{job_id}/{filename}",
  "original_name": "song.mp3",
  "created_at": "2026-02-23T12:34:56Z"
}
Result Queue 메시지
{
  "v": 1,
  "type": "JOB_RESULT",
  "job_id": "uuid",
  "status": "DONE",
  "result": {
    "json_key": "results/{job_id}/analysis.json",
    "html_key": "results/{job_id}/view.html",
    "mp4_key": "results/{job_id}/video.mp4"
  },
  "error": null,
  "finished_at": "2026-02-23T12:35:40Z"
}
DB 테이블 역할
1) s3_objects (파일 단위 카탈로그/감사용)

S3에 실제로 올라간 객체들의 목록 저장

운영 중 누락/고아 객체 확인, 업로드 추적 등에 사용

2) jobs (서비스의 “진짜 상태 테이블”)

job_id 기준으로 업로드 파일 + 결과 파일 + 상태를 묶어서 관리

/api/jobs/{job_id}, /api/jobs/{job_id}/results의 기준

jobs 최소 스키마(권장)
CREATE TABLE IF NOT EXISTS jobs (
  job_id          CHAR(36) PRIMARY KEY,
  upload_s3_key   VARCHAR(1024) NOT NULL,
  original_name   VARCHAR(255)  NOT NULL,
  status          VARCHAR(16)   NOT NULL DEFAULT 'PENDING',

  result_json_key VARCHAR(1024) NULL,
  result_html_key VARCHAR(1024) NULL,
  result_mp4_key  VARCHAR(1024) NULL,
  error_message   TEXT NULL,

  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
WAS API 엔드포인트
GET /api/health

헬스 체크

POST /api/jobs

업로드 → S3 저장 → DB 기록 → SQS(Job Queue) 발행 → status=QUEUED

응답 예시:

{
  "job_id": "...",
  "status": "QUEUED",
  "upload_s3_key": "uploads/{job_id}/{filename}"
}
GET /api/jobs/{job_id}

DB 기준 작업 상태 조회

GET /api/jobs/{job_id}/results

status=DONE일 때 결과 파일들에 대한 presigned URL 반환

(옵션) POST /api/internal/callback

테스트용 콜백(운영은 Result Worker가 Result Queue consume)

환경변수/설정(config)
app/config.py 주요 항목

AWS_REGION

S3_BUCKET

S3_UPLOAD_PREFIX, S3_RESULT_PREFIX

PRESIGN_EXPIRE_SECONDS

JOB_QUEUE_URL, RESULT_QUEUE_URL

CALLBACK_TOKEN(옵션)

DB 접속은 env로 주입(db_client.py가 os.environ 사용)

DB_HOST, DB_PORT, DB_USER, DB_PASS, DB_NAME

현재 구현된 WAS 코드 포인트

업로드 처리: upload_fileobj_to_s3()

S3 객체 로그: upsert_s3_object(bucket, object_key)

작업 row 생성: insert_job_pending(job_id, s3_key, original_name)

큐 발행(=QUEUE 파트): publish_job(...)

상태 업데이트: update_job_status(job_id, "QUEUED"), 실패 시 "FAIL"

남은 작업 체크리스트
필수

 DB에 jobs 테이블 생성 완료 및 컬럼 확인

 queue_client.py 구현 확인 (JOB_QUEUE_URL로 SendMessage)

 온프레미스 AI Worker 구현

Job Queue consume → S3 download → 분석 → S3 upload → Result Queue send

 Result Worker 구현/배포

Result Queue consume → DB에 DONE/FAIL + 결과 키 저장

검증

 업로드 시 S3에 uploads key 생성되는지

 DB jobs row 생성 및 status=QUEUED 확인

 Job Queue에 메시지가 실제로 쌓이는지(SQS 콘솔)

 AI Worker가 메시지 수신/분석/결과 업로드 수행하는지

 Result Queue 메시지 수신 후 jobs가 DONE으로 바뀌는지

 /api/jobs/{job_id}/results에서 presigned URL이 정상 발급되는지