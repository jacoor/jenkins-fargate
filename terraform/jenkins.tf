resource "aws_ecs_task_definition" "jenkins" {
  family                   = "jenkins"
  execution_role_arn       = "${aws_iam_role.ecs_task_execution_role.arn}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"

  container_definitions = <<EOF
[
    {
        "cpu": 0,
        "environment": [
            {
                "name": "JAVA_OPTS",
                "value": "-Dhudson.DNSMultiCast.disabled=true"
            }
        ],
        "essential": true,
        "image": "jenkins/jenkins:2.108-alpine",
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "jenkins",
                "awslogs-region": "us-east-1",
                "awslogs-stream-prefix": "master"
            }
        },
        "mountPoints": [],
        "name": "jenkins",
        "portMappings": [
            {
                "containerPort": 8080,
                "hostPort": 8080,
                "protocol": "tcp"
            },
            {
                "containerPort": 50000,
                "hostPort": 50000,
                "protocol": "tcp"
            }
        ],
        "volumesFrom": []
    }
]
EOF
}

/*
Service needs an iam_role, but the role needs to be an 'service-linked role'. 
It is not possible to create this with terraform https://github.com/terraform-providers/terraform-provider-aws/issues/921
This is not a problem because AWS creates it automatically with the name 'AWSServiceRoleForECS'
*/
resource "aws_ecs_service" "jenkins" {
  name                               = "jenkins"
  cluster                            = "${aws_ecs_cluster.jenkins.id}"
  task_definition                    = "${aws_ecs_task_definition.jenkins.arn}"
  desired_count                      = 1
  launch_type                        = "FARGATE"
  deployment_maximum_percent         = "100"
  deployment_minimum_healthy_percent = "0"

  network_configuration {
    subnets          = ["${module.vpc.private_subnets}"]
    security_groups  = ["${aws_security_group.jenkins.id}"]
    assign_public_ip = "false"
  }

  load_balancer {
    container_name   = "jenkins"
    container_port   = 8080
    target_group_arn = "${module.alb.target_group_arn}"
  }
}

resource "aws_cloudwatch_log_group" "jenkins" {
  name              = "jenkins"
  retention_in_days = 7
}

resource "aws_security_group" "jenkins" {
  name   = "jenkins"
  vpc_id = "${module.vpc.vpc_id}"

  tags {
    Environment = "jenkins"
  }
}

resource "aws_security_group_rule" "jenkins" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "TCP"
  source_security_group_id = "${module.jenkins_http.this_security_group_id}"
  security_group_id        = "${aws_security_group.jenkins.id}"
  description              = "Open to ALB"
}

resource "aws_security_group_rule" "outbound_internet_access_jenkins" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.jenkins.id}"
}
