###########################################
# 1. Jenkins 전용 AIM 유저 생성
# 2. ECR Push 최소 권한 정책 문서 생성
###########################################

# 1. Jenkins 전용 AIM 유저 생성
resource "aws_iam_user" "jenkins" {
  name = "${var.name_prefix}-jenkins"
}

# 2. ECR Push 최소 권한 정책 문서 생성
data "aws_iam_policy_document" "jenkins_ecr_push" {
  statement {
    sid   = "ECRAuth"
    effect = "Allow"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid   = "ECRPushToRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeRepositories",
      "ecr:ListImages"
      ]
      resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_policy" "jenkins_ecr_push" {
  name = "${var.name_prefix}-jenkins-ecr-push"
  policy = data.aws_iam_policy_document.jenkins_ecr_push.json
}

resource "aws_iam_user_policy_attachment" "attach" {
  user        = aws_iam_user.jenkins.name
  policy_arn  = aws_iam_policy.jenkins_ecr_push.arn
}
