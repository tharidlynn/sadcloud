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

create-custodian-role:
	@echo "Creating IAM role: $(CUSTODIAN_ROLE_NAME)"
	@aws iam create-role --role-name $(CUSTODIAN_ROLE_NAME) --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
	@aws iam attach-role-policy --role-name $(CUSTODIAN_ROLE_NAME) --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
	@aws iam put-role-policy --role-name $(CUSTODIAN_ROLE_NAME) --policy-name CloudCustodianMailerPolicy --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["sqs:*"],"Resource":"*"},{"Effect":"Allow","Action":["sns:Publish"],"Resource":"*"}]}'

setup-c7n-mailer:
	@echo "Setting up c7n-mailer"
	@if [ -z "$(from_email)" ] || [ -z "$(slack_webhook)" ]; then \
		echo "Error: from_email and slack_webhook are required. Usage: make setup-c7n-mailer from_email=your_email slack_webhook=your_webhook_url"; \
		exit 1; \
	fi
	@echo "queue_url: https://sqs.$(AWS_REGION).amazonaws.com/$(shell aws sts get-caller-identity --query Account --output text)/$(SQS_QUEUE_NAME)" > mailer.yaml
	@echo "role: arn:aws:iam::$(shell aws sts get-caller-identity --query Account --output text):role/$(CUSTODIAN_ROLE_NAME)" >> mailer.yaml
	@echo "region: $(AWS_REGION)" >> mailer.yaml
	@echo "from_address: $(from_email)" >> mailer.yaml
	@echo "slack_webhook: $(slack_webhook)" >> mailer.yaml
	@c7n-mailer --config mailer.yaml --update-lambda

install-c7n-mailer:
	@echo "Installing c7n-mailer"
	@pip install c7n-mailer

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

