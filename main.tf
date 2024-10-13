provider "aws" {
  region = "us-east-1"
  access_key = "xxx"
  secret_key = "xx"
}



resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
   enable_dns_support             = true
  enable_dns_hostnames           = true
  assign_generated_ipv6_cidr_block = true  # Assign an IPv6 CIDR block automatically

  tags = {
    name = "production-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id

  tags = {
    Name = "prod-vpc"
  }
}

#route table 
# Egress-Only Internet Gateway for IPv6
resource "aws_egress_only_internet_gateway" "ipv6_gateway" {
  vpc_id = aws_vpc.prod-vpc.id

  tags = {
    Name = "prod-ipv6-egress-gateway"
  }
}

# Route Table with both IPv4 and IPv6 routes
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id  # IPv4 traffic via IGW
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.ipv6_gateway.id  # IPv6 traffic via EIGW
  }

  tags = {
    Name = "prod-route-table"
  }
}


# resource "aws_instance" "web" {
#   ami           = "ami-0866a3c8686eaeeba"
#   instance_type = "t2.micro"
  
#   tags = {
#     Name = "ubuntu"
#   }
# }


resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}



# 
# 
# 

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = aws_vpc.prod-vpc.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv6" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv6         = "::/0"  # Allow all IPv6 traffic
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
resource "aws_security_group" "allow_http_ssh" {
  name        = "allow_http_ssh"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  tags = {
    Name = "allow_http_ssh"
  }
}

# Ingress rule for HTTP (port 80)
resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # Allows access from any IPv4 address
  security_group_id = aws_security_group.allow_http_ssh.id
}

# Ingress rule for SSH (port 22)
resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # Allows access from any IPv4 address, you might want to restrict this for security reasons
  security_group_id = aws_security_group.allow_http_ssh.id
}

# Egress rule to allow all outbound traffic
resource "aws_security_group_rule" "allow_all_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allow_http_ssh.id
}

# network interface 
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
security_groups = [aws_security_group.allow_tls.id, aws_security_group.allow_http_ssh.id]

}



resource "aws_eip" "one" {
  
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}


resource "aws_instance" "web-server-instance" {
  ami = "ami-0866a3c8686eaeeba"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "main-key"
  
  network_interface {
    network_interface_id = aws_network_interface.web-server-nic.id
    device_index = 0
  }

  user_data = <<-EOF
  #!/bin/bash
  sudo apt update -y
  sudo apt install apache2 -y
  sudo systemctl start apache2
  sudo bash -c 'echo your very first web server > /var/www/html/index.html'
  EOF

  tags = {
    Name = "web-server"
  }

}

# resource "<provider>_<resource_type> " "name" {
#   config options
#   key =  pair
#   key2 = pair
# }