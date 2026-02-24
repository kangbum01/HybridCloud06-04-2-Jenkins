2차 프로젝트 진행 정리 (WAS–S3–DB–SQS–AI 비동기 파이프라인)
1) 목표 / 요구사항

사용자가 Web에서 음악 파일을 업로드하면:

WAS(FastAPI, ECS) 가 파일을 받아 S3 uploads/{job_id}/{filename} 저장

DB jobs 테이블에 작업 row 생성(PENDING → QUEUED)

WAS가 SQS Job Queue에 분석 요청 메시지 발행(비동기)

AI 서버(온프레) 가 Job Queue consume → 음악 분석 수행

분석 결과를 S3 results/{job_id}/… 로 저장

AI가 SQS Result Queue로 결과 메시지 발행

WAS(또는 Result Worker) 가 Result Queue를 consume 해서 DB jobs를 DONE/FAIL로 업데이트

Web은 /api/jobs/{job_id}와 /api/jobs/{job_id}/results로 상태/결과 URL을 받아 화면 변경

2) 최종 아키텍처 흐름
Web → WAS

POST /api/jobs (multipart/form-data)

file 필수

user_request 선택(기본값 "", 공백이면 기본 모드)

WAS:

S3 업로드

DB jobs insert (PENDING)

SQS Job Queue publish

DB jobs update (QUEUED)

WAS → SQS(Job Queue)

AI 팀 계약 메시지 포맷

{
  "task_id": "<job_id>",
  "s3_audio_key": "uploads/<job_id>/<filename>",
  "user_request": ""
}
AI(온프레) → S3 + SQS(Result Queue)

AI 결과 메시지 포맷(팀 합의)

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
SQS(Result Queue) → WAS(Consumer)

WAS가 Result Queue 메시지를 받아 DB jobs에:

status = DONE/FAIL

result_json_key / result_html_key / result_mp4_key / error_message 업데이트

Web 결과 조회

GET /api/jobs/{job_id}: status 확인

GET /api/jobs/{job_id}/results: DONE일 때 presigned URL 반환

urls.mp4, urls.json, urls.audio(업로드 원본)

3) DB 설계 확정

jobs 테이블만 사용 (s3_objects 제거)

컬럼:

job_id (PK)

upload_s3_key

original_name

status (PENDING/QUEUED/DONE/FAIL)

result_json_key

result_html_key

result_mp4_key

error_message

created_at, updated_at

bucket 컬럼 없음 → bucket은 settings로 고정

4) 네트워크/DB 연결 구조 (가장 중요했던 부분)

WAS VPC: 10.1.0.0/16 (beat-dev)

DR VPC: 10.0.0.0/16 (project2-vpc)

VPC Peering + 라우팅 설정 필요(서브넷 RT 모두 반영 확인)

DB는 직접 연결 대신,
DR VPC의 EC2를 DB Proxy로 사용:

HAProxy TCP 프록시

0.0.0.0:3308 listen → 실제 DB :3306으로 전달

3307은 socat 포트 점유 이슈로 3308로 변경

WAS(ECS) DB 환경변수:

DB_HOST = <Proxy EC2 private IP>

DB_PORT = 3308

5) SQS 구성

Terraform으로 4개 큐 생성:

beat-dev-job-queue

beat-dev-job-dlq

beat-dev-result-queue

beat-dev-result-dlq

DLQ: 재시도 초과 메시지 분리/분석

6) WAS 코드/동작 정리
POST /api/jobs

S3 업로드 → jobs insert(PENDING) → SQS publish → status QUEUED

GET /api/jobs/{job_id}

DB jobs row를 그대로 조회

GET /api/jobs/{job_id}/results

status DONE이면 presign 생성

urls.json/html/mp4 + urls.audio(upload_s3_key) 제공

Result 처리(빠른 완성 버전)

별도 Result Worker 대신 WAS 내부에서 Result Queue consume하여 DB 업데이트 (오늘 마감용)

Front(index.html) 연동

Polling에서 QUEUED도 진행중으로 처리

DONE이면 /results 호출해서 presigned URL을 받아

finalData.videoUrl = urls.mp4

finalData.audioUrl = urls.audio

urls.json이 있으면 fetch해서 분석값 매핑 후 테마 페이지로 전달

분석 JSON 구조가 중첩이라 매핑 필요:

bpm = basic_metrics.bpm

energy = mood_and_vibe.energy_score

brightness = mood_and_vibe.brightness_score

topGenre/probability = ai_top_predictions[0]

7) 해결한 주요 트러블슈팅(핵심 로그/원인)
(1) HAProxy 기동 실패

default_backend 이름 불일치 → frontend/backend 이름 통일

3307 포트 충돌(socat 점유) → 3308로 변경

(2) WAS에서 DB 연결 500

VPC 분리로 DB 접근 불가 → DB 프록시(EC2+HAProxy)로 우회

Task Definition env 반영 안 됨 → 새 revision + Force new deployment

(3) MySQL 인증 플러그인 오류

cryptography 필요 → requirements에 추가

(4) DB Access denied (admin@10.0.1.85)

프록시를 쓰면 DB가 클라이언트를 프록시 IP로 인식

계정/비밀번호/권한 정리 + 실제 접속 DB 일치 확인

(5) SQS AccessDenied

ECS Task Role에 sqs 권한 없어서 SendMessage 실패

JobQueue SendMessage 권한 추가 후 해결

ResultQueue Receive/Delete 권한 추가 후 결과 메시지 소비 시작(메시지 적체 해소)

(6) Web이 화면 변경 안 됨

status 처리/응답 포맷 불일치(옛 PROCESSING/files 구조)

DONE일 때 /results 호출하도록 수정

audio는 /audio 엔드포인트가 아니라 urls.audio presign으로 교체

(7) DB host blocked / timeout

대량 메시지 소비로 DB 연결 폭주 → Host block(1129)

flush-hosts로 해제 후, 타임아웃/재시도 폭주 방지, desired_count 조정 등으로 안정화

8) 현재 “정상 동작 확인한 것”

Web 업로드 → WAS S3 업로드 성공

jobs row 생성(PENDING→QUEUED) 정상

WAS → Job Queue publish 성공

AI(온프레) Job Queue consume 성공

AI 분석 결과 S3 results 경로 업로드 확인

AI → Result Queue 메시지 전송 확인

WAS가 Result Queue consume하여 jobs를 DONE으로 업데이트 확인

/api/jobs/{id}/results에서 presigned json/audio 등 URL 확인

테마 페이지에서 audio 재생 동작 확인