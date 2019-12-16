provider "aws" {
  region = "eu-west-2"
}

############ Networking section #############


resource "aws_vpc" "morawi_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}


# Internet gateway for the load balancer/Public routing table to connect to


resource "aws_internet_gateway" "morawi_internet_gateway" {
  vpc_id = "${aws_vpc.main.id}"

  tags = {
    Name = "mo-rawi-public-gateway"
  }
}


resource "aws_subnet" "morawi-public-subnet-eu-west-2a" {
  vpc_id     = "${aws_vpc.morawi-vpc.id}"
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true # very important, what makes it public
  availability_zone = "eu-west-2a"
  tags = {
  	Name =  "morawi-public-subnet-eu-west-2a"
  }
}

resource "aws_route_table_association" "morawi_internet_route_gateway_association" {
  subnet_id      = ["${aws_subnet.morawi-public-subnet-eu-west-2a.id}","${aws_subnet.morawi-public-subnet-eu-west-2c}"] 
  route_table_id = "${aws_route_table.bar.id}"
}


resource "aws_subnet" "morawi-public-subnet-eu-west-2c" { # Load balancer needs minimum of two public subnets to traverse over
  vpc_id     = "${aws_vpc.morawi-vpc.id}"
  cidr_block = "10.0.3.0/24"
  map_public_ip_on_launch = true # very important, what makes it public
  availability_zone = "eu-west-2c"
  tags = {
  	Name =  "morawi-public-subnet-eu-west-2c"
  }
}

resource "aws_route_table" "morawi-public-route-table" {
    vpc_id = "${aws_vpc.morawi-vpc.id}"

    tags {
        Name = "Public-route-table"
    }
}


resource "aws_route" "morawi-internet-access-route" {
  route_table_id         = "${aws_route_table.morawi-public-route-table.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.morawi_internet_gateway.id}"
}


# Associate subnet public_subnet_eu_west_1a to public route table connectthem together
resource "aws_route_table_association" "morawi-public-subnet-eu-west-2a-association" {
    subnet_id = "${aws_subnet.morawi-public-subnet-eu-west-2a.id}"
    route_table_id = "${aws_route_table.morawi-public-route-table.id}"
}


# For instances representing the 3 tiers to communicate through/within
resource "aws_subnet" "morawi-private-subnet-eu-west-2b" {
  vpc_id     = "${aws_vpc.morawi_vpc.id}"
  cidr_block = "10.0.2.0/24"
  map_public_ip_on_launch = true # very important, what makes it public
  availability_zone = "eu-west-2b"
  tags = {
  	Name =  "morawi-private-subnet-eu-west-2b"
  }
}


resource "aws_route_table" "morawi_private_routing_table" {
  vpc_id = "${aws_vpc.morawi_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    instance_id = "${aws_instance.morawi_nat_instance_gw.id}"
  } 

tags {
    Name = "morawi_private_routing_table"
  }
}


################################ External world facing load balancer & Components #########################################
resource "aws_alb" "morawi-alb" {
  name               = "toptierloadbalancer"
  load_balancer_type = "application"

  subnet_mapping {
    subnets  = ["${morawi-public-subnet-eu-west-2a.id}","${morawi-public-subnet-eu-west-2c.id}"]
    allocation_id = "${aws_eip.morawi.id}"
  }

  
}


resource "aws_alb_listener_rule" "webserver_listener_rule" {
  depends_on   = ["aws_alb_target_group.alb_target"]  
  listener_arn = "${aws_alb_listener.alb_listener.arn}"  
  priority     = "3"   
  action {    
    type             = "forward"    
    target_group_arn = "${aws_alb_target_group.alb_target.id}"  
  }   
  condition {    
    field  = "path-pattern"    
    values = ["/web"]  
  }
}

resource "aws_alb_target_group" "alb_target_webserver" {
  name     = "alb-target-group-webserver" # name must never thave underscores many errors on this
  port     = "80" # Production will replace this with 443
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.morawi_vpc.id}"
  tags {
    name = "aws-alb-target-group-webserver"
  }
}

#Instance Attachment
resource "aws_alb_target_group_attachment" "svc_physical_external" {
  target_group_arn = "${aws_alb_target_group.alb_target_webserver.arn}"
  target_id        = "${aws_instance.webserver.id}"
  port             = 80
}



############################# / External world facing load balancer  & components #######################################




# Create a route to the internet




# Resource SG as in security group


resource "aws_security_group" "SG_morawi_web" { 
  name = "SG_morawi_web" 
  description = "Allow HTTP traffic on 80" # test then transform to 443 once certificate is sorted out 
  vpc_id = "${aws_vpc.morawi-vpc.id}" 
 
  ingress { 
    from_port = 80 
    to_port = 80 
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
  } 
 
  egress { 
    from_port = 0 
    to_port = 0 
    protocol = "-1" 
    cidr_blocks = ["0.0.0.0/0"] 
  } 
} 


# The group below to be used only for testing and problems as, so it can be attached to a testable instance that would also be adjusted with internet access
resource "aws_security_group" "SG_morawi_admin" {
  name = "allow-ssh-22"
  description = "Allow ssh port 22"
  vpc_id = "${aws_vpc.morawi-vpc.id}"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = ["${aws_security_group.SG_morawi_app}","${aws_instance.dbserver}","${aws_security_group.SG_morawi_web}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Here I chose secrurity group fo app server, in this case as its python based, it will be Django, Python based framework.
resource "aws_security_group" "SG_morawi_app" {
  name = "SG_morawi_app"
  description = "Allow HTTP traffic port 8000 Django"
  vpc_id = "${aws_vpc.morawi-vpc.id}"

  ingress {
    from_port = 8000
    to_port = 8000
    protocol = "tcp"
    security_groups = ["${aws_security_group.SG_morawi_web}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = ["${aws_security_group.SG_morawi_db}"]
  }
}

# Scaling group for the ALB

resource "aws_placement_group" "morawi_scaling_placement_group_web" {
  name     = "morawi-placement-group-web"
  strategy = "cluster"
}

resource "aws_autoscaling_group" "morawi_autoscaling_gp_web" {
  name                      = "morawi_autoscaling_gp_web"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 4
  force_delete              = true
  placement_group           = "${aws_placement_group.morawi_scaling_placement_group_web.id}"
  launch_configuration      = "${aws_launch_configuration.mo_rawi_launch_config_web.id}"
  vpc_zone_identifier       = ["${aws_subnet.morawi-public-subnet-eu-west-2a.id}", "${aws_subnet.morawi-public-subnet-eu-west-2c.id}"]

  initial_lifecycle_hook {
    name                 = "foobar"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 2000
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"

    notification_metadata = <<EOF
{
  "foo": "bar"
}
EOF

    notification_target_arn = "arn:aws:sqs:eu-west-2:444455556666:queue1*"
    role_arn                = "arn:aws:iam::123456789012:role/S3Access"
  }

  tag {
    key                 = "foo"
    value               = "bar"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "lorem"
    value               = "ipsum"
    propagate_at_launch = false
  }
}

resource "aws_launch_configuration" "mo_rawi_launch_config_web" {
  name_prefix   = "morawi-launch-config-web"
  image_id      = "ami-00637dd6af24433c3"
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }
}

# security group for Postgresql, this is the chosen db/backend server.
resource "aws_security_group" "SG_morawi_db" {
  name = "SG_morawi_db"
  description = "Allow tcp traffic ports 5432 5433 Postgresql"
  vpc_id = "${aws_vpc.morawi-vpc.id}"

  ingress {
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    security_groups = ["${aws_security_group.SG_morawi_app}","${aws_security_group.SG_morawi_admin}"]
  }

  ingress {
    from_port = 5433
    to_port = 5433
    protocol = "tcp"
    security_groups = ["${aws_security_group.SG_morawi_app}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = ["${aws_security_group.SG_morawi_app}"]
  }
}


resource "aws_autoscaling_attachment" "morawi_asg_attachment" {
  autoscaling_group_name = "${aws_autoscaling_group.morawi_autoscaling_gp_web.id}"
  alb_target_group_arn   = "${aws_alb_target_group.alb_target_webserver.arn}"
}

# Webserver instance tier1


resource "aws_instance" "webserver" {
  ami           = "ami-00637dd6af24433c3"
  instance_type = "t2.micro"
  key_name      = "morawikey"
  
  subnet_id = "${aws_subnet.morawi-morawi-public-subnet-eu-west-2a.id}"
  provisioner "remote-exec" {
    inline = [
      "sudo yum -y update",
      "sudo yum install nginx -y",
      "sudo python -m pip3 install --upgrade pip",
    ]
  }

  vpc_security_group_ids = ["${aws_security_group.SG_morawi_web}"] 
  tags {
    Name = "dbserver-instance"
  }


# Resource instance configuration

resource "aws_instance" "appserver" {
  ami           = "ami-01419b804382064e4"
  instance_type = "t2.micro"
  key_name      = "morawikey"
  
  subnet_id = "${aws_subnet.morawi-morawi-private-subnet-eu-west-2b.id}"
  provisioner "remote-exec" {
    inline = [
      "sudo yum -y update",
      "sudo yum install python3 -y",
      "sudo python -m pip3 install --upgrade pip",
      "sudo pip3 install python-django",
      "pip3 install boto3",
      "pip3 install psycopg2", # Install python driver for Postgresql
    ]
  }

  vpc_security_group_ids = ["${aws_security_group.SG_morawi_app}"] 
  tags {
    Name = "appserver-instance"
  }
}

# The tier 3 DB server

# Resource instance configuration

resource "aws_instance" "dbserver" {
  ami           = "ami-01419b804382064e4"
  instance_type = "t2.micro"
  key_name      = "morawikey"
  
  subnet_id = "${aws_subnet.morawi-private-subnet-eu-west-2a.id}"
  provisioner "remote-exec" {
    inline = [
      "sudo yum -y update",
      "sudo yum install python3 -y",
      "sudo python -m pip3 install --upgrade pip",
      "sudo yum -y install ",
      "sudo -y install postgresql", # install the db of choice
    ]
  }

  vpc_security_group_ids = ["${aws_security_group.SG_morawi_db.id}"] 
  tags {
    Name = "dbserver-instance"
  }

}


resource "aws_instance" "morawi_nat_instance_gw" { # for webserver/tier1, appserver/tier2, dbserver/tier3 to obtain updates from the web without allowing access from out
  ami           = "ami-e1768386"
  subnet_id     = "${aws_subnet.morawi-morawi-public-subnet-eu-west-2a.id}"
  key_name = "morawikey"
  instance_type = "t2.micro"
  source_dest_check = false
  vpc_security_group_ids = ["${aws_security_group.natgateway.id}"]
  associate_public_ip_address = true
  tags {
    Name = "morawi_nat_instance_gw"
  }
}

### Assocciation of routes to subnets

# for webserver and appserver and db server, they will need to communicate via private subnet

resource "aws_route_table_association" "morawi_route_table_association_3tiers_internally" {
  subnet_id      = "${aws_subnet.morawi_private_sub.id}"
  route_table_id = "${aws_route_table.morawi_routing_table_private.id}"
}




}