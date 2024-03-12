terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAZQ3DSSCLF7L4FU52"
  secret_key = "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"
}

resource "aws_instance" "my_first_server" {
  ami           = "ami-07d9b9ddc6cd8dd30"
  instance_type = "t2.micro"

}

data "aws_instances" "existing_instances" {
  instance_tags = {
    # Add any specific tags or filters you want to apply here
  }
}

output "instance_ids" {
  value = data.aws_instances.existing_instances.ids
}

#resource "null_resource" "terminate_instance" {
#  provisioner "local-exce" {
#    command = "aws ec2 terminate-instances --instance-ids i-007ce05873c51bf05"
#  }
#}


# 1. VPC
resource "aws_vpc" "first-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "prod"
  }
}

# 2. Internet GW
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.first-vpc.id

  tags = {
    Name = "main"
  }
}

# 3. Route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.first-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id             = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

# 4. Subnet
resource "aws_subnet" "subnet_1" {
  vpc_id = aws_vpc.first-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "prod-subnet"
  }
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# 6. Security Group
resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.first-vpc.id

  tags = {
    Name = "allow_web"
  }

  ingress {
    description = "HTTPS"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

#resource "aws_vpc_security_group_ingress_rule" "allow_https_ipv4" {
#  description = "HTTPS"
#  security_group_id = aws_security_group.allow_web.id
#  cidr_ipv4         = "0.0.0.0/0"
#  from_port         = 443
#  ip_protocol       = "tcp"
#  to_port           = 443
#}
#
#resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
#  description = "HTTP"
#  security_group_id = aws_security_group.allow_web.id
#  cidr_ipv4         = "0.0.0.0/0"
#  from_port         = 80
#  ip_protocol       = "tcp"
#  to_port           = 80
#}
#
#resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
#  description = "SSH"
#  security_group_id = aws_security_group.allow_web.id
#  cidr_ipv4         = "0.0.0.0/0"
#  from_port         = 22
#  ip_protocol       = "tcp"
#  to_port           = 22
#}
#
#resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
#  security_group_id = aws_security_group.allow_web.id
#  cidr_ipv4         = "0.0.0.0/0"
#  ip_protocol       = "-1" # semantically equivalent to all ports
#}
#
#resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
#  security_group_id = aws_security_group.allow_web.id
#  cidr_ipv6         = "::/0"
#  ip_protocol       = "-1" # semantically equivalent to all ports
#}
#
# 7. network interface
resource "aws_network_interface" "web" {
  subnet_id       = aws_subnet.subnet_1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

}

# 8. EIP
resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

# 9. Create Ubuntu server and install apache2
resource "aws_instance" "web-ins" {
  ami           = "ami-0cd59ecaf368e5ccf"
  instance_type = "t2.micro"
  availability_zone = "us-east-1b"
  key_name = "vpc_key_pair"
#  associate_public_ip_address = true

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web.id
  }

  user_data = <<-EOF
#! /bin/bash
sudo apt update -y
sudo apt install apache2 -y
sudo systemctl start apache2
sudo bash -c "echo your very first web server > /var/www/html/index.html"
EOF
  tags = {
    Name = "web-server"
  }
}

####