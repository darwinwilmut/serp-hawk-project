# ── EC2 ───────────────────────────────────────────────────────────────────────

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.crm.id
}

output "ec2_public_ip" {
  description = "Elastic IP address - point your domain A record here"
  value       = aws_eip.crm.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_eip.crm.public_ip}"
}

# ── EBS ───────────────────────────────────────────────────────────────────────

output "data_volume_id" {
  description = "Additional EBS volume ID (attached at /dev/xvdf, mounted at /AWSVOL)"
  value       = aws_ebs_volume.data.id
}

output "data_volume_az" {
  description = "Availability zone of the data EBS volume"
  value       = aws_ebs_volume.data.availability_zone
}

# ── S3 ────────────────────────────────────────────────────────────────────────

output "s3_bucket_name" {
  description = "S3 uploads bucket name - set as S3_BUCKET_NAME in .env"
  value       = aws_s3_bucket.uploads.id
}

output "s3_bucket_arn" {
  description = "S3 uploads bucket ARN"
  value       = aws_s3_bucket.uploads.arn
}

# ── IAM ───────────────────────────────────────────────────────────────────────

output "iam_role_name" {
  description = "IAM role attached to the EC2 instance for S3 access"
  value       = aws_iam_role.ec2_s3.name
}

output "iam_instance_profile" {
  description = "IAM instance profile attached to EC2"
  value       = aws_iam_instance_profile.ec2_s3.name
}

# ── .env reminder ─────────────────────────────────────────────────────────────

output "env_reminder" {
  description = "Values to copy into your EC2 .env file"
  value       = <<-EOT

    Add these to /opt/crm/.env on the EC2 instance:

      S3_BUCKET_NAME=${aws_s3_bucket.uploads.id}
      AWS_REGION=${var.aws_region}

    No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY needed.
    The EC2 instance role handles S3 authentication automatically.

    Point your domain A record to: ${aws_eip.crm.public_ip}
  EOT
}
