FROM jenkins/jenkins:lts
USER root

# 컨테이너 내부에 ansible 설치
# ca-certificates : https 통신 안정성
RUN apt-get update && apt-get install -y \
    git \
    curl \
    jq \
    awscli \
    docker.io \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*


# Jenkins 플러그인 (2차용 최소)
# - configuration-as-code : JCasC
# - workflow-aggregator   : Pipeline
# - git                   : 소스 체크아웃
# - job-dsl               : seed job(파이프라인 자동 생성) 사용 시
# - credentials-binding   : AWS 키를 credentials로 바인딩
# - aws-credentials       : AmazonWebServiceCredentialsBinding 제공
RUN jenkins-plugin-cli --plugins \
    configuration-as-code \
    workflow-aggregator \
    git \
    job-dsl \
    credentials-binding \
    aws-credentials

USER jenkins
# JCasC 환경 변수 설정
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs/jenkins.yaml

