terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region-name
}

resource "aws_vpc" "BlayVPC" {
  cidr_block = var.vpc_cidr
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.BlayVPC.id
}

resource "aws_route_table" "PublicRT" {
  vpc_id = aws_vpc.BlayVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRT"
  }
}

resource "aws_subnet" "custom_public_subnet1" {
  vpc_id                  = aws_vpc.BlayVPC.id
  cidr_block              = var.subnet1_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.az1

  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "custom_public_subnet2" {
  vpc_id                  = aws_vpc.BlayVPC.id
  cidr_block              = var.subnet2_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.az2

  tags = {
    Name = "PublicSubnet2"
  }
}

resource "aws_route_table_association" "Public_subnet_association1" {
  subnet_id      = aws_subnet.custom_public_subnet1.id
  route_table_id = aws_route_table.PublicRT.id
}

resource "aws_route_table_association" "Public_subnet_association2" {
  subnet_id      = aws_subnet.custom_public_subnet2.id
  route_table_id = aws_route_table.PublicRT.id
}

resource "aws_instance" "app_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.custom_public_subnet1.id

  tags = {
    Name = "Blay-Terraform"
  }
}

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.BlayVPC.id

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_security_group_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
}

resource "aws_security_group_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_tls.id
  type              = "egress"
  ipv6_cidr_blocks  = ["::/0"]
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
}

resource "aws_lb" "web_alb" {
  name               = "Blayapp-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls.id]
  subnets            = [aws_subnet.custom_public_subnet1.id, aws_subnet.custom_public_subnet2.id]

  enable_deletion_protection = true

  tags = {
    Environment = "lab"
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.BlayVPC.id

  tags = {
    Name = "alb_sg"
  }
}

resource "aws_security_group_rule" "alb_sg_http" {
  security_group_id = aws_security_group.alb_sg.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.BlayVPC.id

  tags = {
    Name = "rds_sg"
  }
}

resource "aws_security_group_rule" "rds_sg_mysql" {
  security_group_id = aws_security_group.rds_sg.id
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
   cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_launch_template" "Blay_LC" {
  name_prefix   = "Blay_Web_Config"
  image_id      = var.ami_id
  instance_type = var.instance_type

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "BlayASG-instance"
    }
  }

  block_device_mappings {
    device_name           = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp2"
      delete_on_termination = true
    }
  }

  vpc_security_group_ids = [aws_security_group.allow_tls.id]
}


resource "aws_autoscaling_group" "Blay_ASG" {
  launch_template {
    id      = aws_launch_template.Blay_LC.id
    version = "$Latest"
  }

  min_size          = 2
  max_size          = 10
  desired_capacity  = 2
  health_check_type = "EC2"
  health_check_grace_period = 300

  vpc_zone_identifier = [aws_subnet.custom_public_subnet1.id, aws_subnet.custom_public_subnet2.id]
}

resource "aws_db_subnet_group" "blaydb_subnet_group" {
  name       = "blaydb_subnet_group"
  subnet_ids = [aws_subnet.custom_public_subnet1.id, aws_subnet.custom_public_subnet2.id]
}

resource "aws_db_instance" "blaydb_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  db_name                 = "blay_db"
  username             = "Blay"
  password             = "Metro123"
  db_subnet_group_name = aws_db_subnet_group.blaydb_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
}

resource "aws_s3_bucket" "private_bucket" {
  bucket = "blays3bucket"
 acl   = "private"

  tags = {
    Name = "privateBucket"
  }
}

resource "aws_iam_role" "blayiam_role" {
  name               = "blayiam-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "blayiam_policy" {
  name        = "Blayiam-policy"
  description = "Policy for EC2 to access S3"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "s3:*"
      Resource  = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "Blayiam_attachment" {
  role       = aws_iam_role.blayiam_role.name
  policy_arn = aws_iam_policy.blayiam_policy.arn
}