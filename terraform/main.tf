# ─────────────────────────────────────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────────────────────────────────────

# Latest Ubuntu 22.04 LTS AMI (Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Default VPC - avoids creating/managing a custom VPC for simplicity
data "aws_vpc" "default" {
  default = true
}

# Pick the first available subnet in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Group
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "crm" {
  name        = "${var.project_name}-sg"
  description = "SerpHawk CRM - allow HTTP, HTTPS, and restricted SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH - restrict to your IP via ssh_allowed_cidr variable"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP - nginx redirects to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS - nginx terminates TLS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EC2 Instance
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "crm" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.crm.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3.name

  # Root volume - OS, nginx config, app code cloned from git
  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true

    tags = {
      Name        = "${var.project_name}-root"
      Environment = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-ec2"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Additional EBS Volume (data volume)
# Stores all Docker data - images, containers, and named volumes (pg_data)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.crm.availability_zone
  type              = "gp2"
  size              = var.data_volume_size_gb

  # Retain volume on destroy so PostgreSQL data is not lost accidentally.
  # To delete it, run: terraform destroy -target=aws_ebs_volume.data
  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "${var.project_name}-data"
    Environment = var.environment
  }
}

resource "aws_volume_attachment" "data" {
  device_name  = "/dev/xvdf"       # appears as /dev/xvdf on t2.micro (Xen)
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.crm.id
  force_detach = false
}

# ─────────────────────────────────────────────────────────────────────────────
# Elastic IP
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eip" "crm" {
  domain = "vpc"

  # Associate after volume is attached so the instance is fully ready
  depends_on = [aws_volume_attachment.data]

  tags = {
    Name        = "${var.project_name}-eip"
    Environment = var.environment
  }
}

resource "aws_eip_association" "crm" {
  instance_id   = aws_instance.crm.id
  allocation_id = aws_eip.crm.id
}

# ─────────────────────────────────────────────────────────────────────────────
# S3 - file uploads bucket
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "uploads" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = var.s3_bucket_name
    Environment = var.environment
  }
}

# Allow public GetObject on the uploads/ prefix so file URLs work in the browser
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "uploads_public_read" {
  bucket = aws_s3_bucket.uploads.id

  # Depends on public access block being applied first
  depends_on = [aws_s3_bucket_public_access_block.uploads]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadUploads"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.uploads.arn}/uploads/*"
      }
    ]
  })
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["https://*"]
    max_age_seconds = 3600
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM - EC2 instance role (boto3 picks up credentials automatically)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "ec2_s3" {
  name        = "${var.project_name}-ec2-role"
  description = "Allows EC2 to access the CRM uploads S3 bucket"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "ec2_s3" {
  name = "${var.project_name}-s3-policy"
  role = aws_iam_role.ec2_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.uploads.arn}/uploads/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_s3" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.ec2_s3.name
}
