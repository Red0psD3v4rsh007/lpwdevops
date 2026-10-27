#!/bin/bash
# =============================================================================
# PR4 Deploy Script: Flask App → AWS ECR → ECS Fargate + Lambda
# Author: PR4 Practical
# =============================================================================

set -e  # Exit on any error

# ── CONFIGURATION ─────────────────────────────────────────────────────────────
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-YOUR_AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-YOUR_AWS_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="us-east-1"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
ECR_REPO="pr4-flask-app"
ECS_CLUSTER="pr4-cluster"
ECS_SERVICE="pr4-service"
TASK_FAMILY="pr4-task"
LAMBDA_NAME="pr4-ecs-invoker"
LAMBDA_ROLE="pr4-lambda-role"
EXEC_ROLE="ecsTaskExecutionRole"
LOG_GROUP="/ecs/pr4-task"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"

echo "================================================================"
echo "  PR4 Deployment — AWS ECS + ECR + Lambda"
echo "  Account: ${ACCOUNT_ID}"
echo "  Region : ${REGION}"
echo "================================================================"

# ── STEP 1: Create ECR Repository ─────────────────────────────────────────────
echo ""
echo "STEP 1: Creating ECR Repository..."
aws ecr create-repository \
    --repository-name ${ECR_REPO} \
    --image-scanning-configuration scanOnPush=true \
    2>/dev/null && echo "  ✓ ECR repo created: ${ECR_URI}" \
    || echo "  ✓ ECR repo already exists: ${ECR_URI}"

# ── STEP 2: Docker Build & Push to ECR ────────────────────────────────────────
echo ""
echo "STEP 2: Building Docker image..."
aws ecr get-login-password --region ${REGION} | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

docker build -t ${ECR_REPO}:latest .
docker tag ${ECR_REPO}:latest ${ECR_URI}:latest
docker push ${ECR_URI}:latest
echo "  ✓ Image pushed to: ${ECR_URI}:latest"

# ── STEP 3: Create CloudWatch Log Group ───────────────────────────────────────
echo ""
echo "STEP 3: Creating CloudWatch Log Group..."
aws logs create-log-group --log-group-name ${LOG_GROUP} 2>/dev/null \
    && echo "  ✓ Log group created: ${LOG_GROUP}" \
    || echo "  ✓ Log group already exists: ${LOG_GROUP}"

# ── STEP 4: Create ECS Task Execution Role ────────────────────────────────────
echo ""
echo "STEP 4: Creating ECS Task Execution Role..."
cat > /tmp/ecs-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ecs-tasks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name ${EXEC_ROLE} \
    --assume-role-policy-document file:///tmp/ecs-trust-policy.json \
    2>/dev/null && echo "  ✓ Role created: ${EXEC_ROLE}" \
    || echo "  ✓ Role already exists: ${EXEC_ROLE}"

aws iam attach-role-policy \
    --role-name ${EXEC_ROLE} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
    2>/dev/null && echo "  ✓ Attached AmazonECSTaskExecutionRolePolicy"

# ── STEP 5: Register ECS Task Definition ──────────────────────────────────────
echo ""
echo "STEP 5: Registering ECS Task Definition..."

EXEC_ROLE_ARN=$(aws iam get-role --role-name ${EXEC_ROLE} --query Role.Arn --output text)

aws ecs register-task-definition \
    --family ${TASK_FAMILY} \
    --network-mode awsvpc \
    --requires-compatibilities FARGATE \
    --cpu "512" \
    --memory "1024" \
    --execution-role-arn ${EXEC_ROLE_ARN} \
    --container-definitions "[
        {
            \"name\": \"web\",
            \"image\": \"${ECR_URI}:latest\",
            \"portMappings\": [{\"containerPort\": 5000, \"hostPort\": 5000, \"protocol\": \"tcp\"}],
            \"environment\": [
                {\"name\": \"REDIS_HOST\", \"value\": \"localhost\"},
                {\"name\": \"FLASK_APP\", \"value\": \"app.py\"}
            ],
            \"essential\": true,
            \"logConfiguration\": {
                \"logDriver\": \"awslogs\",
                \"options\": {
                    \"awslogs-group\": \"${LOG_GROUP}\",
                    \"awslogs-region\": \"${REGION}\",
                    \"awslogs-stream-prefix\": \"ecs\"
                }
            }
        },
        {
            \"name\": \"redis\",
            \"image\": \"redis:alpine\",
            \"portMappings\": [{\"containerPort\": 6379, \"hostPort\": 6379, \"protocol\": \"tcp\"}],
            \"essential\": true,
            \"logConfiguration\": {
                \"logDriver\": \"awslogs\",
                \"options\": {
                    \"awslogs-group\": \"${LOG_GROUP}\",
                    \"awslogs-region\": \"${REGION}\",
                    \"awslogs-stream-prefix\": \"ecs\"
                }
            }
        }
    ]" \
    --query taskDefinition.taskDefinitionArn --output text

echo "  ✓ Task definition registered: ${TASK_FAMILY}"

# ── STEP 6: Create ECS Cluster ────────────────────────────────────────────────
echo ""
echo "STEP 6: Creating ECS Cluster..."
aws ecs create-cluster \
    --cluster-name ${ECS_CLUSTER} \
    --capacity-providers FARGATE \
    --query cluster.status --output text
echo "  ✓ Cluster: ${ECS_CLUSTER}"

# ── STEP 7: Get Default VPC + Subnet + Create Security Group ──────────────────
echo ""
echo "STEP 7: Configuring VPC networking..."
VPC_ID=$(aws ec2 describe-vpcs \
    --filters Name=isDefault,Values=true \
    --query Vpcs[0].VpcId --output text)
echo "  ✓ VPC: ${VPC_ID}"

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters Name=vpc-id,Values=${VPC_ID} Name=defaultForAz,Values=true \
    --query Subnets[0].SubnetId --output text)
echo "  ✓ Subnet: ${SUBNET_ID}"

# Create security group for ECS task
SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=pr4-ecs-sg Name=vpc-id,Values=${VPC_ID} \
    --query SecurityGroups[0].GroupId --output text 2>/dev/null)

if [ "${SG_ID}" == "None" ] || [ -z "${SG_ID}" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name pr4-ecs-sg \
        --description "PR4 ECS Flask App Security Group" \
        --vpc-id ${VPC_ID} \
        --query GroupId --output text)
    # Allow inbound port 5000 (Flask)
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp --port 5000 --cidr 0.0.0.0/0
    echo "  ✓ Security group created: ${SG_ID} (port 5000 open)"
else
    echo "  ✓ Security group exists: ${SG_ID}"
fi

# ── STEP 8: Create ECS Service ────────────────────────────────────────────────
echo ""
echo "STEP 8: Creating ECS Service..."
aws ecs create-service \
    --cluster ${ECS_CLUSTER} \
    --service-name ${ECS_SERVICE} \
    --task-definition ${TASK_FAMILY} \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
    --query service.serviceArn --output text \
    2>/dev/null && echo "  ✓ Service created: ${ECS_SERVICE}" \
    || echo "  ✓ Service already exists, updating..." && \
    aws ecs update-service \
        --cluster ${ECS_CLUSTER} \
        --service ${ECS_SERVICE} \
        --task-definition ${TASK_FAMILY} \
        --desired-count 1 \
        --query service.serviceArn --output text

echo "  ✓ ECS Service running. Waiting for task to start (60s)..."
sleep 60

# ── STEP 9: Get Public IP of running task ─────────────────────────────────────
echo ""
echo "STEP 9: Getting task public IP..."
TASK_ARN=$(aws ecs list-tasks \
    --cluster ${ECS_CLUSTER} \
    --service-name ${ECS_SERVICE} \
    --desired-status RUNNING \
    --query taskArns[0] --output text 2>/dev/null || echo "None")

if [ "${TASK_ARN}" != "None" ] && [ -n "${TASK_ARN}" ]; then
    ENI_ID=$(aws ecs describe-tasks \
        --cluster ${ECS_CLUSTER} \
        --tasks ${TASK_ARN} \
        --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
        --output text)
    PUBLIC_IP=$(aws ec2 describe-network-interfaces \
        --network-interface-ids ${ENI_ID} \
        --query NetworkInterfaces[0].Association.PublicIp \
        --output text 2>/dev/null || echo "pending")
    echo "  ✓ Task ARN: ${TASK_ARN}"
    echo "  ✓ Public IP: ${PUBLIC_IP}"
    echo "  ✓ Flask App URL: http://${PUBLIC_IP}:5000"
else
    echo "  ⚠ Task not yet running. Check ECS console."
fi

# ── STEP 10: Create Lambda IAM Role ──────────────────────────────────────────
echo ""
echo "STEP 10: Creating Lambda IAM Role..."
aws iam create-role \
    --role-name ${LAMBDA_ROLE} \
    --assume-role-policy-document file://trust-policy.json \
    2>/dev/null && echo "  ✓ Lambda role created: ${LAMBDA_ROLE}" \
    || echo "  ✓ Lambda role already exists: ${LAMBDA_ROLE}"

# Attach permissions: Lambda basic + ECS full + EC2 read
aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    2>/dev/null
aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE} \
    --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess \
    2>/dev/null
aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE} \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess \
    2>/dev/null
echo "  ✓ Policies attached to Lambda role"
echo "  Waiting 10s for IAM propagation..."
sleep 10

# ── STEP 11: Deploy Lambda Function ──────────────────────────────────────────
echo ""
echo "STEP 11: Deploying Lambda Function..."
LAMBDA_ROLE_ARN=$(aws iam get-role --role-name ${LAMBDA_ROLE} --query Role.Arn --output text)

# Package Lambda
zip -j /tmp/lambda_function.zip lambda_function.py

# Deploy or update Lambda
aws lambda create-function \
    --function-name ${LAMBDA_NAME} \
    --runtime python3.12 \
    --role ${LAMBDA_ROLE_ARN} \
    --handler lambda_function.lambda_handler \
    --zip-file fileb:///tmp/lambda_function.zip \
    --timeout 30 \
    --environment "Variables={ECS_CLUSTER=${ECS_CLUSTER}}" \
    --description "PR4: Invokes ECS API to list/describe/stop tasks" \
    --query FunctionArn --output text \
    2>/dev/null && echo "  ✓ Lambda function created: ${LAMBDA_NAME}" \
    || (
        aws lambda update-function-code \
            --function-name ${LAMBDA_NAME} \
            --zip-file fileb:///tmp/lambda_function.zip \
            --query FunctionArn --output text
        echo "  ✓ Lambda function updated: ${LAMBDA_NAME}"
    )

# ── STEP 12: Test Lambda ──────────────────────────────────────────────────────
echo ""
echo "STEP 12: Testing Lambda (list_tasks)..."
sleep 5  # Wait for Lambda to be ready

aws lambda invoke \
    --function-name ${LAMBDA_NAME} \
    --payload '{"action": "list_tasks"}' \
    --cli-binary-format raw-in-base64-out \
    /tmp/lambda_output.json

echo "  ✓ Lambda Response:"
cat /tmp/lambda_output.json | python3 -m json.tool

echo ""
echo "STEP 12b: Testing Lambda (describe_tasks)..."
aws lambda invoke \
    --function-name ${LAMBDA_NAME} \
    --payload '{"action": "describe_tasks"}' \
    --cli-binary-format raw-in-base64-out \
    /tmp/lambda_output2.json

cat /tmp/lambda_output2.json | python3 -m json.tool

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  PR4 DEPLOYMENT COMPLETE!"
echo "================================================================"
echo "  ECR Repository : ${ECR_URI}"
echo "  ECS Cluster    : ${ECS_CLUSTER}"
echo "  ECS Service    : ${ECS_SERVICE}"
echo "  Lambda         : ${LAMBDA_NAME}"
if [ -n "${PUBLIC_IP}" ] && [ "${PUBLIC_IP}" != "pending" ]; then
    echo "  Flask App URL  : http://${PUBLIC_IP}:5000"
fi
echo ""
echo "  To test Flask app:"
echo "    curl http://<PUBLIC_IP>:5000"
echo ""
echo "  To invoke Lambda via CLI:"
echo "    aws lambda invoke --function-name ${LAMBDA_NAME} \\"
echo "      --payload '{\"action\": \"list_tasks\"}' \\"
echo "      --cli-binary-format raw-in-base64-out output.json"
echo "================================================================"
echo ""
echo "  CLEANUP COMMAND (run when done):"
echo "    bash cleanup.sh"
echo "================================================================"
