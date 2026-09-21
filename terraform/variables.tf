variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "serphawk-crm"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair used for SSH access"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to reach port 22 — restrict to your IP (e.g. 203.0.113.5/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro" # free tier eligible
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB (OS + Docker images)"
  type        = number
  default     = 20 # keep under 30 GB total to stay within free tier
}

variable "data_volume_size_gb" {
  description = "Additional EBS volume size in GB (Docker volumes — PostgreSQL data lives here)"
  type        = number
  default     = 10 # root 20 GB + data 10 GB = 30 GB total (free tier limit)
}

variable "s3_bucket_name" {
  description = "Globally unique name for the S3 uploads bucket"
  type        = string
  default     = "serphawk-crm-uploads"
}

variable "environment" {
  description = "Deployment environment tag"
  type        = string
  default     = "production"
}
