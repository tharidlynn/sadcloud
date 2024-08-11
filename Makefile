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

create-backend-bucket:
	@echo "Creating S3 bucket: $(S3_TERRAFORM_BACKEND_BUCKET_NAME)"
	@aws s3api create-bucket --bucket $(S3_TERRAFORM_BACKEND_BUCKET_NAME) --region $(AWS_REGION)

create-cloud-custodian-bucket:
	@echo "Creating S3 bucket: $(S3_CLOUD_CUSTODIAN_BUCKET_NAME)"
	@aws s3api create-bucket --bucket $(S3_CLOUD_CUSTODIAN_BUCKET_NAME) --region $(AWS_REGION)

create-terracost-bucket:
	@echo "Creating S3 bucket: $(S3_TERRACOST_BUCKET_NAME)"
	@aws s3api create-bucket --bucket $(S3_TERRACOST_BUCKET_NAME) --region $(AWS_REGION)

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

