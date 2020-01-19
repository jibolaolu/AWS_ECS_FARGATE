# Creating the ECS files and resource
provider "aws" {
  region ="${var.region}"
}

#Creating s3 backend configuration
terraform {
    backend "s3" {}
}

#Data to read the remote infrastructure state
data "terraform_remote_state" "infrastructure" {
  backend = "s3"

  config {
      region = "${var.region}"
      bucket = "${var.remote_state_bucket}"
      key    = "${var.remote_state_key}"
  }
}

##Create the ECS Cluster
resource "aws_ecs_cluster" "production-fargate-cluster" {
  name = "Production_Fargate-Cluster"
}

##Create an Application Load Balancer

resource "aws_alb" "ecs_cluster_alb" {
  name = "${var.ecs_cluster_name}-ALB"
  internal = false
  security_groups = ["${aws_security_group.ecs_alb_security_group.id}"]
  subnets = ["${split(",", join(",", data.terraform_remote_state.infrastructure.public_subnets))}"]

  tags = {
    Name = "${var.ecs_cluster_name}-ALB"
  }
}

##Create an HTTPS Listner
resource "aws_alb_listener" "ecs_alb_https_listner" {
  load_balancer_arn = "${aws_alb.ecs_cluster_alb.arn}"
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = "${aws_acm_certificate.ecs_domain_certificate.arn}"
  default_action {
    type = "forward"
    target_group_arn = "${aws_alb_target_group.ecs_default_target_group.arn}"
  }
}
## Create a Default Target group

resource "aws_alb_target_group" "ecs_default_target_group" {
  name = "${var.ecs_cluster_name}-TG"
  port = 80
  protocol = "HTTP"
  vpc_id = "${data.terraform_remote_state.infrastructure.vpc_id}"

  tags = {
    Name = "${var.ecs_cluster_name}-TG"
  }
  depends_on = ["aws_alb_target_group.ecs_default_target_group"]
}
##Create the Route 53 record for the load balancer

resource "aws_route53_record" "aws_load_balancer_record" {
  name = "*. ${var.ecs_domain_name}"
  type = "A"
  zone_id = "${data.aws_route53_zone.ecs_domain.id}"
  alias {
    evaluate_target_health = false
    name                   = "${aws_alb.ecs_cluster_alb.dns_name}"
    zone_id                = "${aws_alb.ecs_cluster_alb.zone_id}"
  }
}

##Creating an IAM-Role

resource "aws_iam_role" "ecs_cluster_role" {
  name = "${var.ecs_cluster_name}-IAM-ROLE"
  assume_role_policy = <<EOF
{
"Version": "2012-10-17"
"Statement": [
   {
     "Effect": "Allow",
     "Principal": {
       "Service": ["ecs.amazonaws.com", "ec2.amazonaws.com", "application-autoscaling.amazonaws.com"]
      },
      "Action": "sts:AssumeRole"
   }
   ]
}
EOF
}

##Create IAM Policy

resource "aws_iam_role_policy" "ecs_cluster_ploicy" {
  name   = "${var.ecs_cluster_name}-IAM-Policy"
  role   = "${aws_iam_role.ecs_cluster_role.id}"
  policy = <<EOF
}