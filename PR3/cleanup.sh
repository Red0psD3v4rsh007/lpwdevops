#!/bin/bash
# =============================================================================
# PR4 Cleanup Script — Remove all AWS resources created during PR4
# =============================================================================

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-YOUR_AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-YOUR_AWS_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="us-east-1"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

echo "================================================================"
echo "  PR4 Cleanup — Removing all AWS Resources"
echo "================================================================"

echo "Deleting ECS Service..."
aws ecs update-service --cluster pr4-cluster --service pr4-service --desired-count 0 2>/dev/null
aws ecs delete-service --cluster pr4-cluster --service pr4-service --force 2>/dev/null && echo "  ✓ ECS Service deleted"

echo "Deleting ECS Cluster..."
aws ecs delete-cluster --cluster pr4-cluster 2>/dev/null && echo "  ✓ ECS Cluster deleted"

echo "Deleting Lambda..."
aws lambda delete-function --function-name pr4-ecs-invoker 2>/dev/null && echo "  ✓ Lambda deleted"

echo "Deleting ECR Repository..."
aws ecr delete-repository --repository-name pr4-flask-app --force 2>/dev/null && echo "  ✓ ECR repo deleted"

echo "Deleting CloudWatch Log Group..."
aws logs delete-log-group --log-group-name /ecs/pr4-task 2>/dev/null && echo "  ✓ Log group deleted"

echo "Deleting IAM Roles..."
aws iam detach-role-policy --role-name pr4-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null
aws iam detach-role-policy --role-name pr4-lambda-role --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess 2>/dev/null
aws iam detach-role-policy --role-name pr4-lambda-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess 2>/dev/null
aws iam delete-role --role-name pr4-lambda-role 2>/dev/null && echo "  ✓ Lambda role deleted"

aws iam detach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null
aws iam delete-role --role-name ecsTaskExecutionRole 2>/dev/null && echo "  ✓ ECS execution role deleted"

echo "Deleting Security Group..."
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=pr4-ecs-sg --query SecurityGroups[0].GroupId --output text 2>/dev/null)
if [ "${SG_ID}" != "None" ] && [ -n "${SG_ID}" ]; then
    aws ec2 delete-security-group --group-id ${SG_ID} 2>/dev/null && echo "  ✓ Security group deleted"
fi

echo ""
echo "================================================================"
echo "  Cleanup complete! All PR4 AWS resources removed."
echo "================================================================"
