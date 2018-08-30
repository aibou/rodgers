Go Pack Go!

# About

AWSのもろもろをSlackBot経由で操作するやつです

[図を入れて解説する]

# Setup

## Push to ECR

## Create Task Role

信頼関係は以下の通りECS Taskのサービスを登録する

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sts:AssumeRole"
            ],
            "Resource": [
                "arn:aws:iam::[子アカウントのアカウントID]:role/[子アカウントで使うロール名]",
                "arn:aws:iam::[子アカウントのアカウントID]:role/[子アカウントで使うロール名]"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameter"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```

> 子アカウントが複数ある場合は、それぞれの子アカウントIDを記載する必要がある。 アカウントID部分に `*` は使えない
> 子アカウントで使うロール名は、子アカウント複数ある場合は同一名称である必要がある。

## Create ECS Task Definition

TODO: ACCOUNT_ROLE_NAME, SLACK_API_TOKEN

## Create ECS Cluster & Services

ここは省略します。

## 子アカウントに親アカウントからassume roleさせるためのロールを作成する

## 親アカウントのEC2 System Manager ParameterStoreでアカウント名とアカウントIDを登録する