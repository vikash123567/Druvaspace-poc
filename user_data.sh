#!/bin/bash
set -e
exec > /var/log/satellite-startup.log 2>&1

SATELLITE_ID="__SATELLITE_ID__"
PROCESSING_SCOPE="__PROCESSING_SCOPE__"
PASS_START_TIME="__PASS_START_TIME__"
PASS_END_TIME="__PASS_END_TIME__"

REGION="ap-south-1"
ACCOUNT_ID="185863138492"
ECR_REPO="satellite-poc-repo"
ENVIRONMENT="dev"

echo "================================================"
echo " Satellite      : $SATELLITE_ID"
echo " Scope          : $PROCESSING_SCOPE"
echo " Pass Start     : $PASS_START_TIME"
echo " Pass End       : $PASS_END_TIME"
echo "================================================"

# Install Docker and jq
yum update -y
yum install -y docker jq
systemctl start docker
systemctl enable docker
echo "Docker installed"

# ECR Login
aws ecr get-login-password --region $REGION | \
  docker login --username AWS \
  --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
echo "ECR login successful"

# Fetch config from SSM
CONFIG=$(aws ssm get-parameter \
  --region $REGION \
  --name "/isocs/satellite/$SATELLITE_ID/$ENVIRONMENT/config" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

RABBITMQ_URL=$(echo $CONFIG | jq -r '.RABBITMQ_URL')
DOCDB_URI=$(echo $CONFIG    | jq -r '.DOCDB_URI')
echo "Config fetched from SSM"

ECR_IMAGE="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:latest"
docker pull $ECR_IMAGE
echo "Image pulled"

# ── Start containers based on PROCESSING_SCOPE ──────

if [ "$PROCESSING_SCOPE" = "both" ] || [ "$PROCESSING_SCOPE" = "encoding" ]; then
    docker run -d \
      --name central-agentprocessing \
      --restart unless-stopped \
      -e SERVICE_NAME=central-agentprocessing \
      -e SATELLITE_ID=$SATELLITE_ID \
      -e RABBITMQ_URL=$RABBITMQ_URL \
      -e DOCDB_URI=$DOCDB_URI \
      -e PROCESSING_SCOPE=$PROCESSING_SCOPE \
      -e PASS_START_TIME=$PASS_START_TIME \
      -e PASS_END_TIME=$PASS_END_TIME \
      $ECR_IMAGE
    echo "central-agentprocessing started"
fi

if [ "$PROCESSING_SCOPE" = "both" ] || [ "$PROCESSING_SCOPE" = "decoding" ]; then
    docker run -d \
      --name data-decoding \
      --restart unless-stopped \
      -e SERVICE_NAME=data-decoding \
      -e SATELLITE_ID=$SATELLITE_ID \
      -e RABBITMQ_URL=$RABBITMQ_URL \
      -e DOCDB_URI=$DOCDB_URI \
      -e PROCESSING_SCOPE=$PROCESSING_SCOPE \
      -e PASS_START_TIME=$PASS_START_TIME \
      -e PASS_END_TIME=$PASS_END_TIME \
      $ECR_IMAGE
    echo "data-decoding started"
fi

echo "================================================"
echo " All services running for $SATELLITE_ID"
echo "================================================"
