# app/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
  model_config = SettingsConfigDict(env_file=".env", extra="ignore")

  AWS_REGION: str = "ap-northeast-2"
  S3_BUCKET: str = "ai-project-result"

  S3_UPLOAD_PREFIX: str = "uploads"
  S3_RESULT_PREFIX: str = "results"
  PRESIGN_EXPIRE_SECONDS: int = 3600

  CALLBACK_TOKEN: str = "change-me"  # 테스트용 유지 옵션

  JOB_QUEUE_URL: str 
  RESULT_QUEUE_URL: str 
settings = Settings()
