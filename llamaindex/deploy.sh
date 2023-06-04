#!/usr/bin/env bash

export VER=${VER:-local-$(date +%Y%m%d%H%M)}

aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $(aws sts get-caller-identity | jq -r .Account).dkr.ecr.ap-northeast-1.amazonaws.com
docker build . -t 326914400610.dkr.ecr.ap-northeast-1.amazonaws.com/my-gpt:${VER}
docker push 326914400610.dkr.ecr.ap-northeast-1.amazonaws.com/my-gpt:${VER}

envsubst < fargate/api-definition.json > fargate/task-definition.json

aws ecs register-task-definition --cli-input-json file://$PWD/fargate/task-definition.json --profile me