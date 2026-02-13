from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
  model_config = SettingsConfigDict(env_file="env", extra="ignore")

  # 이거 나중에 변경을 좀 해야하나?
  AI_BASE_URL: str = "http://127/0.0.1:9000"
  AI_AUTH_TOKEN: str = ""
  CALLBACK_TOKEN: str = "change-me"
  UPLOAD_DIR: str = "/tmp/uploads"

settings = Settings()
