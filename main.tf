
resource "aws_vpc" "morawi_vpc" {
     cidr_block = "${var.vpc_cidr}"
     enable_dns_hostnames = true
     enable_dns_support   = true
}

resource "aws_subnet" "morawi_public_sub" {

     vpc_id = "${aws_vpc.morawi_vpc.id}"
     cidr_block = "${var.public_subnet_cidr}" # for the ALB reason
     availability_zone = "eu-west-2a"
     map_public_ip_on_launch = true   # Giving Nginx public access
}

resource "aws_subnet" "morawi_private_sub" {
       vpc_id = "${aws_vpc.morawi_vpc.id}"
       cidr_block = "${var.private_subnet_cidr}"
       availability_zone = "eu-west-2b" # ensure spread over multipe zones for resilience
       map_public_ip_on_launch = false
}



resource "aws_subnet" "morawi_public_sub2" {

     vpc_id = "${aws_vpc.morawi_vpc.id}"
     cidr_block = "${var.public_subnet_cidr_alb}" # for the ALB reason
     availability_zone = "eu-west-2c"
     map_public_ip_on_launch = true   # Giving Nginx public access
}

