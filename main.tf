provider "aws" {

}

resource "aws_vpc" "prod" {
  cidr_block = var.VPC_cidr_block
  tags = {

    Name = "prod-vpc"
  }
}

resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.prod.id

  tags = {
    Name = "prod-IGW"
  }

}

resource "aws_subnet" "prod_public_subnet" {
  vpc_id                  = aws_vpc.prod.id
  availability_zone       = "ap-south-1a"
  cidr_block              = var.prod_public_subnet
  map_public_ip_on_launch = true


  tags = {
    Name = "public_subnet"
  }
}

resource "aws_route_table" "prod_rt" {
  vpc_id = aws_vpc.prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }
}

resource "aws_route_table_association" "public_subnet" {
  route_table_id = aws_route_table.prod_rt.id
  subnet_id      = aws_subnet.prod_public_subnet.id
}

#add

resource "aws_instance" "web" {
  ami                         = "ami-02d26659fd82cf299" # Change AMI
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = aws_subnet.prod_public_subnet.id
  
user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install -y nginx unzip awscli

              # Download artifact from private S3 bucket
              aws s3 cp s3://${var.bucket_name}/website.zip /tmp/website.zip

              # Extract the website to nginx root directory
              unzip /tmp/website.zip -d /var/www/html

              systemctl restart nginx
              EOF

  tags = {
    Name = "WebServer"
  }
}


resource "aws_security_group" "web" {
  name   = "web-security_group"
  vpc_id = aws_vpc.prod.id
}

locals {
  allowed_ports = {
    "22"  = 22
    "80"  = 80
    "443" = 443
  }
}

resource "aws_security_group_rule" "allow_multiple_ports" {
  security_group_id = aws_security_group.web.id
  for_each          = local.allowed_ports
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_ssh_egress" {
  security_group_id = aws_security_group.web.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]

}




resource "aws_s3_bucket" "test" {
  bucket = var.bucket_name
  acl    = "private"
  versioning {
    enabled = true
  }

  tags = {
    Name        = "example-bucket"
    Environment = "dev"
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "test" {
  bucket = var.bucket_name
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_policy" "s3_read_policy" {
  name        = "s3-read-policy"
  description = "Allow EC2 to read objects from private S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["arn:aws:s3:::${var.bucket_name}/*"]
    }]
  })
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "ec2-s3-read-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach Policy to Role
resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}




output "vpc_id" {
  value = aws_vpc.prod.id
}

output "subnet_id" {
  value = aws_subnet.prod_public_subnet.id
}