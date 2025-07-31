terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC for BGP topology
resource "aws_vpc" "bgp_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "bgp-topology-vpc"
    Project = "bgp-prototype"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "bgp_igw" {
  vpc_id = aws_vpc.bgp_vpc.id

  tags = {
    Name = "bgp-igw"
    Project = "bgp-prototype"
  }
}

# Subnets across multiple AZs
resource "aws_subnet" "bgp_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.bgp_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "bgp-subnet-${count.index + 1}"
    Project = "bgp-prototype"
  }
}

# Route table
resource "aws_route_table" "bgp_rt" {
  vpc_id = aws_vpc.bgp_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.bgp_igw.id
  }

  tags = {
    Name = "bgp-route-table"
    Project = "bgp-prototype"
  }
}

# Route table associations
resource "aws_route_table_association" "bgp_rta" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.bgp_subnets[count.index].id
  route_table_id = aws_route_table.bgp_rt.id
}

# Security Group for BGP routers
resource "aws_security_group" "bgp_sg" {
  name        = "bgp-router-sg"
  description = "Security group for BGP routers"
  vpc_id      = aws_vpc.bgp_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # BGP port
  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # ICMP for ping
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bgp-router-sg"
    Project = "bgp-prototype"
  }
}

# EC2 instances for BGP routers
resource "aws_instance" "bgp_routers" {
  count         = var.router_count
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  subnet_id                   = aws_subnet.bgp_subnets[count.index % length(var.availability_zones)].id
  vpc_security_group_ids      = [aws_security_group.bgp_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    router_id = count.index + 1
    router_count = var.router_count
  })

  tags = {
    Name = "bgp-router-${count.index + 1}"
    Project = "bgp-prototype"
    Role = "bgp-router"
  }

  depends_on = [aws_internet_gateway.bgp_igw]
}

# S3 bucket for logs and data
resource "aws_s3_bucket" "bgp_logs" {
  bucket = "${var.project_name}-bgp-logs-${random_string.bucket_suffix.result}"

  tags = {
    Name = "bgp-logs-bucket"
    Project = "bgp-prototype"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "bgp_logs_versioning" {
  bucket = aws_s3_bucket.bgp_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# IAM role for EC2 instances to access S3
resource "aws_iam_role" "bgp_ec2_role" {
  name = "bgp-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bgp_ec2_profile" {
  name = "bgp-ec2-profile"
  role = aws_iam_role.bgp_ec2_role.name
}

resource "aws_iam_role_policy" "bgp_s3_policy" {
  name = "bgp-s3-policy"
  role = aws_iam_role.bgp_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.bgp_logs.arn,
          "${aws_s3_bucket.bgp_logs.arn}/*"
        ]
      }
    ]
  })
}

# Outputs
output "router_public_ips" {
  description = "Public IPs of BGP routers"
  value       = aws_instance.bgp_routers[*].public_ip
}

output "router_private_ips" {
  description = "Private IPs of BGP routers"
  value       = aws_instance.bgp_routers[*].private_ip
}

output "s3_bucket_name" {
  description = "S3 bucket for logs"
  value       = aws_s3_bucket.bgp_logs.bucket
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.bgp_vpc.id
} 