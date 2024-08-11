.PHONY: create-backend-storage set-env init init-backend plan apply apply-auto destroy destroy-module validate output fmt state refresh

# Set the default environment to "dev"
ENV ?= dev

# Terraform Directory
TF_DIR = sadcloud

# Terraform Plans
PLAN = tfplan  # Plan file will be generated in the current directory context

# Define default editor, default to nano if not set
EDITOR ?= vi

# Accept project and secret IDs as command-line arguments with default values
PROJECT_ID ?= "foobar-9989"

S3_TERRAFORM_BACKEND_BUCKET_NAME="diraht-sadcloud-terraform-state"
S3_CLOUD_CUSTODIAN_BUCKET_NAME="diraht-sadcloud-cloud-custodian"
S3_TERRACOST_BUCKET_NAME="diraht-sadcloud-terracost"

AWS_REGION="us-east-1"


SQS_QUEUE_NAME="diraht-sadcloud-cloud-custodian-mailer-queue"
CUSTODIAN_ROLE_NAME="diraht-sadcloud-cloud-custodian-role"

run-custodian:
	@echo "Running Cloud Custodian..."
	@cd $(TF_DIR) && \
	OUTPUT_DIR="custodian-output-$(shell date +%Y-%m-%d_%H-%M-%S)" && \
	mkdir -p $$OUTPUT_DIR && \
	custodian run --output-dir=$$OUTPUT_DIR custodian-policies.yaml
	@echo "Cloud Custodian run complete. Output saved in $$OUTPUT_DIR. Check your Slack channel for notifications."

update-lambda:
	c7n-mailer --config sadcloud/mailer.yaml --update-lambda

create-custodian-role:
	@echo "Checking if IAM role $(CUSTODIAN_ROLE_NAME) exists..."
	@if aws iam get-role --role-name $(CUSTODIAN_ROLE_NAME) >/dev/null 2>&1; then \
		echo "Role $(CUSTODIAN_ROLE_NAME) already exists. Deleting it..."; \
		aws iam list-role-policies --role-name $(CUSTODIAN_ROLE_NAME) --query 'PolicyNames[]' --output text | xargs -n 1 aws iam delete-role-policy --role-name $(CUSTODIAN_ROLE_NAME) --policy-name; \
		aws iam list-attached-role-policies --role-name $(CUSTODIAN_ROLE_NAME) --query 'AttachedPolicies[].PolicyArn' --output text | xargs -n 1 aws iam detach-role-policy --role-name $(CUSTODIAN_ROLE_NAME) --policy-arn; \
		aws iam delete-role --role-name $(CUSTODIAN_ROLE_NAME); \
		echo "Waiting for role deletion to complete..."; \
		sleep 10; \
	fi
	@echo "Creating IAM role: $(CUSTODIAN_ROLE_NAME)"
	@aws iam create-role --role-name $(CUSTODIAN_ROLE_NAME) --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["lambda.amazonaws.com","events.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
	@aws iam attach-role-policy --role-name $(CUSTODIAN_ROLE_NAME) --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
	@aws iam put-role-policy --role-name $(CUSTODIAN_ROLE_NAME) --policy-name CloudCustodianPolicy --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetBucketLocation\",\"s3:ListAllMyBuckets\",\"s3:ListBucket\",\"s3:GetBucketPolicy\",\"s3:GetBucketAcl\",\"s3:PutBucketAcl\",\"s3:PutBucketPolicy\",\"s3:DeleteBucketPolicy\",\"s3:PutBucketPublicAccessBlock\"],\"Resource\":\"*\"},{\"Effect\":\"Allow\",\"Action\":[\"sqs:*\"],\"Resource\":\"*\"},{\"Effect\":\"Allow\",\"Action\":[\"sns:Publish\"],\"Resource\":\"*\"},{\"Effect\":\"Allow\",\"Action\":[\"lambda:GetFunction\",\"lambda:ListFunctions\",\"lambda:GetPolicy\"],\"Resource\":\"*\"},{\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"arn:aws:logs:*:*:*\"},{\"Effect\":\"Allow\",\"Action\":[\"iam:PassRole\"],\"Resource\":\"arn:aws:iam::*:role/$(CUSTODIAN_ROLE_NAME)\"}]}"
	@echo "IAM role $(CUSTODIAN_ROLE_NAME) created with necessary permissions"


test-custodian:
	@echo "Testing Cloud Custodian policies"
	@echo "Making $(S3_TERRACOST_BUCKET_NAME) bucket public..."
	@aws s3api put-public-access-block --bucket $(S3_TERRACOST_BUCKET_NAME) --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
	@echo '{"Version":"2012-10-17","Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":["s3:GetObject","s3:ListBucket"],"Resource":["arn:aws:s3:::diraht-sadcloud-terracost","arn:aws:s3:::diraht-sadcloud-terracost/*"]}]}' > /tmp/public-policy.json
	@aws s3api put-bucket-policy --bucket $(S3_TERRACOST_BUCKET_NAME) --policy file:///tmp/public-policy.json
	@echo "Running Cloud Custodian..."
	@cd $(TF_DIR) && custodian run --output-dir=. custodian-policies.yaml
	@echo "Checking if Cloud Custodian corrected the public access..."
	@aws s3api get-public-access-block --bucket $(S3_TERRACOST_BUCKET_NAME)
	@echo "Checking if Cloud Custodian removed the public policy..."
	@aws s3api get-bucket-policy --bucket $(S3_TERRACOST_BUCKET_NAME) || echo "Bucket policy removed successfully"
	@echo "Test complete. Check your Slack channel for notifications."
	@rm -f /tmp/public-policy.json

create-backend-bucket:
	@echo "Creating S3 bucket: $(S3_TERRAFORM_BACKEND_BUCKET_NAME)"
	@aws s3api create-bucket --bucket $(S3_TERRAFORM_BACKEND_BUCKET_NAME) --region $(AWS_REGION)

create-cloud-custodian-bucket:
	@echo "Creating S3 bucket: $(S3_CLOUD_CUSTODIAN_BUCKET_NAME)"
	@aws s3api create-bucket --bucket $(S3_CLOUD_CUSTODIAN_BUCKET_NAME) --region $(AWS_REGION)

create-terracost-bucket:
	@echo "Creating S3 bucket: $(S3_TERRACOST_BUCKET_NAME)"
	@aws s3api create-bucket --bucket $(S3_TERRACOST_BUCKET_NAME) --region $(AWS_REGION)

create-sqs-queue:
	@echo "Creating SQS queue: $(SQS_QUEUE_NAME)"
	@aws sqs create-queue --queue-name $(SQS_QUEUE_NAME) --region $(AWS_REGION)

create-custodian-resources: create-sqs-queue create-custodian-role create-cloud-custodian-bucket

setup-custodian: install-c7n-mailer create-custodian-resources setup-c7n-mailer

set-env:
	@if [ -z "$(secret_id)" ]; then \
		echo "Error: secret_id argument is required. Usage: make set-env secret_id=your_secret_id"; \
		exit 1; \
	fi
	@echo "Using Project ID: $(PROJECT_ID)"
	@echo "Using Secret ID: $(secret_id)"
	@echo "Opening editor for .env file..."
	@$(EDITOR) /tmp/.env_tmp
	@echo "Uploading .env to Google Cloud Secret Manager..."
	@gcloud secrets versions add $(secret_id) --data-file=/tmp/.env_tmp --project=$(PROJECT_ID)
	@rm -f /tmp/.env_tmp
	@echo "Done"


# Initialize Terraform
init:
	cd $(TF_DIR) && terraform init

init-backend:
	@if [ -z "$(bucket)" ]; then \
		echo "Error: bucket argument is required. Usage: make init-backend bucket=your_bucket_name [prefix=your_prefix]"; \
		exit 1; \
	fi
	@echo "Initializing Terraform with bucket: $(bucket) and prefix: $(prefix)"
	cd $(TF_DIR) && terraform init -backend-config="bucket=$(bucket)" $(if $(prefix),-backend-config="prefix=$(prefix)")

# Run Terraform plan
plan:
	cd $(TF_DIR) && terraform plan

# Run Terraform plan and save the output to a file
plan-save:
	cd $(TF_DIR) && terraform plan -out=$(PLAN)

# Apply Terraform 
apply:
	cd $(TF_DIR) && terraform apply 

apply-auto:
	cd $(TF_DIR) && terraform apply --auto-approve

# Apply Terraform plan
apply-save:
	cd $(TF_DIR) && terraform apply "$(PLAN)"

# Destroy Terraform managed infrastructure
destroy:
	cd $(TF_DIR) && terraform destroy

# Destroy specific module
destroy-module:
	@if [ -z "$(module)" ]; then \
		echo "Error: module argument is required. Usage: make destroy-module module=module_name"; \
		exit 1; \
	fi
	cd $(TF_DIR) && terraform destroy -target=module.$(module)

# Validate Terraform files
validate:
	cd $(TF_DIR) && terraform validate

# Output Terraform outputs
output:
	cd $(TF_DIR) && terraform output

# Format Terraform files
fmt:
	cd $(TF_DIR) && terraform fmt -recursive

# Show Terraform state
state:
	cd $(TF_DIR) && terraform state list

# Refresh Terraform state
refresh:
	cd $(TF_DIR) && terraform refresh

