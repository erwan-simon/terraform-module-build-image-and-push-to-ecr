# Terraform Module: Build Image and Push to ECR

* [I. Project Overview](#i-project-overview)
* [II. Architecture / Design](#ii-architecture--design)
* [III. Prerequisites](#iii-prerequisites)
* [IV. Installation / Setup](#iv-installation--setup)
* [V. Usage](#v-usage)
* [VI. Infrastructure](#vi-infrastructure)
* [VII. Configuration](#vii-configuration)
* [VIII. Project Structure](#viii-project-structure)
* [IX. Limitations / Assumptions](#ix-limitations--assumptions)

## I. Project Overview

This is a reusable Terraform module that automates the creation of an AWS Elastic Container Registry (ECR) repository and the build and push workflow for Docker images. It is designed to simplify the deployment of containerized applications by encapsulating infrastructure provisioning and image management into a single module.

The module is intended for developers and DevOps engineers who need to:
- Provision ECR repositories with configurable policies
- Build Docker images from local source code
- Automatically push built images to ECR as part of Terraform execution
- Manage image tags and rebuild triggers

## II. Architecture / Design

The module consists of two primary components:

### A. Infrastructure Provisioning
- **ECR Repository**: Creates an AWS ECR repository with configurable settings (tag mutability, image scanning, force delete).
- **ECR Policy**: Optionally attaches a resource-based policy to the ECR repository for cross-account or service access control.

### B. Image Build and Upload Workflow
- **Build Trigger**: Uses a Terraform `null_resource` with a `local-exec` provisioner to execute a shell script.
- **Docker Build**: The shell script (`upload_image_to_registry.sh`) performs the following:
  1. Navigates to the provided code path containing the Dockerfile
  2. Optionally assumes an IAM role if cross-account access is required
  3. Retrieves the latest image tag from ECR for cache optimization
  4. Builds the Docker image using `docker buildx` with cache-from and cache-to inline strategies
  5. Authenticates to ECR using AWS credentials
  6. Pushes the built image to the ECR repository with the specified tag

### Component Interaction
1. Terraform creates the ECR repository
2. The `null_resource` executes the upload script as a local provisioner
3. The script interacts with AWS services (ECR, STS) to build and push the image
4. The script execution is triggered on Terraform apply and whenever the `image_rebuild_trigger` value changes

## III. Prerequisites

- **Terraform**: Version compatible with AWS provider and `null_resource` provisioner (recommend Terraform >= 1.0)
- **AWS CLI**: Installed and accessible in the PATH for ECR authentication and role assumption
- **Docker**: Installed locally with `docker buildx` support for building and pushing images
- **AWS Credentials**: Valid AWS credentials configured (via environment variables, AWS CLI profile, or IAM instance profile)
- **IAM Permissions**: The executing user/role must have permissions to:
  - Create and manage ECR repositories
  - Push images to ECR
  - Assume roles (if `role_to_assume_arn` is used)
  - Query AWS account identity and region information
- **Source Code**: A directory containing a valid `Dockerfile` at the path specified by `code_path`

## IV. Installation / Setup

### A. Module Usage

This module is designed to be referenced from a parent Terraform configuration. It is not a standalone application.

**Example module invocation:**

```hcl
module "ecr_build_and_push" {
  source = "git::https://github.com/your-org/terraform-module-build-image-and-push-to-ecr.git//iac?ref=v1.0.0"

  ecr_name               = "my-application"
  code_path              = "${path.root}/../app"
  image_tag              = "v1.2.3"
  image_tag_mutability   = "IMMUTABLE"
  image_rebuild_trigger  = filemd5("${path.root}/../app/Dockerfile")
  role_to_assume_arn     = "arn:aws:iam::123456789012:role/ECRPushRole"

  tags_map = {
    project_name = "myproject"
    domain_name  = "myapp"
    stage_name   = "dev"
  }

  ecr_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::123456789012:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      }
    ]
  })
}
```

### B. Local Development Setup

1. Clone the repository (if developing or extending the module):
   ```bash
   git clone <repository-url>
   cd terraform-module-build-image-and-push-to-ecr
   ```

2. Ensure Docker and AWS CLI are installed:
   ```bash
   docker --version
   aws --version
   ```

3. Configure AWS credentials:
   ```bash
   aws configure
   ```

## V. Usage

### A. Module Invocation

Reference this module from your Terraform configuration as shown in the Installation section. The module will:
1. Create the ECR repository on `terraform apply`
2. Automatically build the Docker image from the specified `code_path`
3. Push the image to the newly created ECR repository

### B. Triggering Rebuilds

By default, the image is rebuilt on every `terraform apply` due to the timestamp-based trigger. To control when rebuilds occur, set the `image_rebuild_trigger` variable to a value that changes only when you want to rebuild:

```hcl
image_rebuild_trigger = filemd5("${path.root}/path/to/Dockerfile")
```

This will trigger a rebuild only when the Dockerfile content changes.

### C. Role Assumption for Cross-Account Access

If the Terraform execution context does not have direct permissions to push to ECR (e.g., CI/CD pipelines in different AWS accounts), provide the `role_to_assume_arn` variable:

```hcl
role_to_assume_arn = "arn:aws:iam::TARGET_ACCOUNT_ID:role/ECRPushRole"
```

The shell script will assume this role before interacting with ECR.

## VI. Infrastructure

### A. Resources Created

1. **aws_ecr_repository.main**
   - Name: Defined by `var.ecr_name`
   - Image tag mutability: Configurable (MUTABLE or IMMUTABLE)
   - Image scanning: Enabled on push
   - Force delete: Enabled (repository can be destroyed even if it contains images)
   - Tags: Applied from `var.tags_map`

2. **aws_ecr_repository_policy.main** (optional)
   - Conditionally created if `var.ecr_policy` is provided
   - Applies a resource-based policy to the ECR repository

3. **null_resource.ecr_upload**
   - Executes `upload_image_to_registry.sh` to build and push the Docker image
   - Triggered by changes to `image_rebuild_trigger` variable

### B. Data Sources

- **aws_caller_identity.current**: Retrieves the AWS account ID
- **aws_region.current**: Retrieves the current AWS region

### C. Deployment Workflow

The module is designed to be used within a Terraform configuration. Typical workflow:
1. Define the module in your Terraform code
2. Run `terraform init` to initialize the module
3. Run `terraform plan` to preview changes
4. Run `terraform apply` to create the ECR repository and push the image

**Note**: The Docker build and push happen during `terraform apply` as a local provisioner execution. Ensure Docker daemon is running locally.

## VII. Configuration

### A. Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `ecr_name` | string | Name of the ECR repository to create |
| `tags_map` | map(string) | Map of tags to apply to AWS resources |
| `code_path` | string | Absolute or relative path to the directory containing the Dockerfile |

### B. Optional Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `image_tag` | string | `"latest"` | Tag to apply to the built Docker image |
| `image_tag_mutability` | string | `"MUTABLE"` | Whether image tags can be overwritten (MUTABLE or IMMUTABLE) |
| `image_rebuild_trigger` | string | `""` | String value that triggers rebuild when changed. Defaults to timestamp if empty |
| `role_to_assume_arn` | string | `""` | ARN of IAM role to assume before pushing to ECR (optional) |
| `ecr_policy` | string | `null` | JSON-formatted ECR resource policy (optional) |

### C. Outputs

| Output | Description |
|--------|-------------|
| `ecr_name` | The name of the created ECR repository |
| `ecr_url` | The full URL of the ECR repository |
| `ecr_arn` | The ARN of the ECR repository |
| `code_path` | Echo of the input `code_path` variable |

### D. Environment Variables

The `upload_image_to_registry.sh` script expects AWS credentials to be available via:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (if using temporary credentials)

These are typically inherited from the Terraform execution environment.

## VIII. Project Structure

```
.
├── iac/                          # Terraform module source code
│   ├── data.tf                   # Data sources for AWS account and region
│   ├── ecr.tf                    # ECR repository resource definition
│   ├── ecr_policy.tf             # Optional ECR repository policy resource
│   ├── locals.tf                 # Local variables (rebuild trigger logic)
│   ├── outputs.tf                # Module outputs
│   ├── upload_image_to_registry.sh   # Shell script for Docker build and push
│   ├── upload_image_to_registry.tf   # null_resource for script execution
│   └── variables.tf              # Input variable definitions
├── .github/
│   └── workflows/
│       └── release.yml           # GitHub Actions workflow for semantic releases
├── .gitlab-ci.yml                # GitLab CI configuration (mirrors to GitHub)
├── .releaserc.json               # Semantic-release configuration
├── .gitignore                    # Git ignore rules
└── LICENSE                       # MIT License
```

### A. Core Terraform Module (`iac/`)

The `iac/` directory contains all Terraform configuration files:
- **ecr.tf**: Defines the ECR repository with scanning and tagging
- **ecr_policy.tf**: Conditionally attaches an ECR repository policy
- **upload_image_to_registry.tf**: Manages the image build/push lifecycle using a null_resource
- **upload_image_to_registry.sh**: Bash script that performs Docker build, ECR authentication, and image push
- **data.tf**: Queries AWS account ID and region
- **locals.tf**: Computes the rebuild trigger (timestamp if not provided)
- **variables.tf**: Declares all input variables
- **outputs.tf**: Exposes ECR repository information

### B. CI/CD and Release Automation

- **.gitlab-ci.yml**: Configures GitLab CI to mirror the repository to GitHub
- **.github/workflows/release.yml**: Automates semantic versioning and releases on GitHub using semantic-release
- **.releaserc.json**: Configuration for semantic-release (branches, plugins, changelog generation)

## IX. Limitations / Assumptions

1. **Local Execution Requirement**
   - The module uses a `local-exec` provisioner, meaning Docker must be installed and running on the machine executing Terraform.
   - This module is not suitable for Terraform Cloud or other remote execution environments without Docker access.

2. **Dockerfile Location**
   - The `code_path` must contain a valid `Dockerfile` at its root.
   - The module does not validate the existence of the Dockerfile before execution.

3. **AWS Region**
   - The module uses the current AWS region from the Terraform provider configuration or AWS CLI default.
   - Per organizational conventions, the default region is `eu-west-1` unless explicitly configured otherwise.

4. **Image Cache Strategy**
   - The shell script attempts to use the latest image in the ECR repository as a build cache.
   - If the ECR repository is empty (first run), the cache-from step will fail silently, and the build proceeds without cache.

5. **Rebuild Trigger Behavior**
   - If `image_rebuild_trigger` is not set, the module uses `timestamp()`, causing a rebuild on every `terraform apply`.
   - To avoid unnecessary rebuilds, explicitly set `image_rebuild_trigger` to a stable value (e.g., hash of Dockerfile or source code).

6. **Role Assumption**
   - When `role_to_assume_arn` is provided, the script assumes the role using `aws sts assume-role`.
   - The role must have a trust policy allowing the executing principal to assume it.
   - The script temporarily replaces AWS credentials, which may have side effects if other processes rely on the original credentials during execution.

7. **GitLab as Source of Truth**
   - Per organizational conventions, this repository is primarily hosted on GitLab.
   - The GitHub repository is a mirror for release management.
   - CI/CD is implemented in GitLab CI, not GitHub Actions (except for release automation).

8. **Terraform Backend**
   - The module does not define a backend configuration. It is expected to be used as a child module within a parent Terraform configuration that manages its own backend.

9. **Docker Buildx**
   - The script uses `docker buildx build` with inline caching and provenance disabled.
   - Ensure Docker Buildx is installed and enabled on the execution machine.

10. **Tagging Conventions**
    - The module applies tags from `tags_map` to the ECR repository.
    - Per organizational conventions, these should include `project_name`, `domain_name`, and `stage_name` for cost allocation tracking.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
