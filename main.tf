#---------------------------------#
# SKO 2020 - Terraform demo #
#                                 #
# Deploys two webservers to AWS   #
#---------------------------------#
# Configure AWS connection, secrets are in terraform.tfvars
provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

# Get availability zones for the region specified in var.region
data "aws_availability_zones" "all" {}

# Create autoscaling policy -> target at a 70% average CPU load
resource "aws_autoscaling_policy" "SKO2020-asg-policy-1" {
  name                   = "SKO2020-asg-policy"
  policy_type            = "TargetTrackingScaling"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.SKO2020-asg.name}"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Create an autoscaling group
resource "aws_autoscaling_group" "SKO2020-asg" {
  name                 = "SKO2020-asg"
  launch_configuration = "${aws_launch_configuration.SKO2020-lc.id}"
  availability_zones = [
    "${data.aws_availability_zones.all.names}",
  ]
  min_size = 2
  max_size = 10
  load_balancers = [
    "${aws_elb.SKO2020-elb.name}",
  ]
  health_check_type = "ELB"
  tag {
    key                 = "Name"
    value               = "SKO2020-ASG"
    propagate_at_launch = true
  }
}

# Create launch configuration
resource "aws_launch_configuration" "SKO2020-lc" {
  name          = "SKO2020-lc"
  image_id      = "ami-5652ce39"
  instance_type = "t2.nano"
  key_name      = "${var.key_name}"
  security_groups = [
    "${aws_security_group.SKO2020-lc-sg.id}",
  ]
  iam_instance_profile = "${var.iam_instance_profile}"
  user_data            = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install httpd -y
              sudo service httpd start
              sudo chkconfig httpd on
              aws s3 cp "${var.s3_bucket}" /var/www/html/ --recursive
              hostname -f >> /var/www/html/index.html
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

# Create the ELB
resource "aws_elb" "SKO2020-elb" {
  name = "SKO2020-elb"
  security_groups = [
    "${aws_security_group.SKO2020-elb-sg.id}",
  ]
  availability_zones = [
    "${data.aws_availability_zones.all.names}",
  ]
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    #target = "TCP:${var.server_port}"
    target = "HTTP:${var.server_port}/index.html"
  }
  # This adds a listener for incoming HTTP requests.
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = "${var.server_port}"
    instance_protocol = "http"
  }
}

# Create security group that's applied the launch configuration
resource "aws_security_group" "SKO2020-lc-sg" {
  name = "SKO2020-lc-sg"
  # Inbound HTTP from anywhere
  ingress {
    from_port = "${var.server_port}"
    to_port   = "${var.server_port}"
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  ingress {
    from_port = "${var.ssh_port}"
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  lifecycle {
    to_port               = "${var.ssh_port}"
    create_before_destroy = true
  }
}

# Create security group that's applied to the ELB
resource "aws_security_group" "SKO2020-elb-sg" {
  name = "SKO2020-elb-sg"
  # Allow all outbound
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  # Inbound HTTP from anywhere
  ingress {
    from_port = "80"
    to_port   = "80"
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

module "test_server_max" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "2.13.0"
  # A list of security group IDs to associate with
  vpc_security_group_ids = []
  # The type of instance to start
  instance_type = ""
  # Name to be used on all resources as prefix
  name = ""
  # Specify one or more IPv6 addresses from the range of the subnet to associate with the primary network interface
  ipv6_addresses = []
  # ID of AMI to use for the instance
  ami = module.ec2-instance.ami
  # If true, the EC2 instance will have associated public IP address
  associate_public_ip_address = true
  # A number of IPv6 addresses to associate with the primary network interface. Amazon EC2 chooses the IPv6 addresses from the range of your subnet.
  ipv6_address_count = 1
  # Can be used instead of user_data to pass base64-encoded binary data directly. Use this instead of user_data whenever the value is not a valid UTF-8 string. For example, gzip-encoded user data must be base64-encoded and passed via this argument to avoid corruption.
  user_data_base64 = ""
  # The user data to provide when launching the instance. Do not pass gzip-compressed data via this argument; see user_data_base64 instead.
  user_data = ""
  # Private IP address to associate with the instance in a VPC
  private_ip = ""
}
