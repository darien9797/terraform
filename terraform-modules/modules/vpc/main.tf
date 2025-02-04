
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Public Subnets (For SSM Host EC2)
resource "aws_subnet" "public_subnet_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-southeast-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "192.168.2.0/24"
  availability_zone = "ap-southeast-1b"
  map_public_ip_on_launch = true
}

# Private Subnets (For EC2 Server & RDS)
resource "aws_subnet" "private_subnet_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "192.168.3.0/24"
  availability_zone = "ap-southeast-1a"
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "192.168.4.0/24"
  availability_zone = "ap-southeast-1b"
}

#Internet gateway for public subnet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# NAT Gateway for Private Subnets
resource "aws_eip" "nat" {}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet_1.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "private_nat_access" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "allow_ssh_ssm" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_access" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.allow_ssh_ssm.id]
  }
}

# EC2 Instances
resource "aws_instance" "ssm_host" {
  ami           = "ami-0672fd5b9210aa093"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet_1.id
  security_groups = [aws_security_group.allow_ssh_ssm.id]
  #iam_instance_profile = "ssm-role"
}

resource "aws_instance" "private_server" {
  ami           = "ami-0672fd5b9210aa093"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet_1.id
  security_groups = [aws_security_group.rds_access.id]
}

# RDS MariaDB

resource "aws_db_subnet_group" "mariadb" {
  name       = "mariadb-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}


resource "aws_db_instance" "mariadb" {
  identifier          = "mariadb-instance"
  engine             = "mariadb"
  instance_class     = "db.t3.micro"
  allocated_storage  = 20
  username          = "admin"
  password          = "password123"
  #subnet_group_name  = aws_db_subnet_group.mariadb.name
  vpc_security_group_ids = [aws_security_group.rds_access.id]
  skip_final_snapshot = true
}

resource "aws_db_instance" "replica" {
  engine         = "mariadb"
  instance_class = "db.t3.micro"
  replicate_source_db = aws_db_instance.mariadb.id
}


#load balancer
resource "aws_lb" "nlb" {
  name               = "public-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
}

# Create Target Group for NLB
resource "aws_lb_target_group" "nlb_tg" {
  name     = "nlb-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id
}

# NLB Listener
resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_tg.arn
  }
}



