##### Initialize
provider "aws" {
  version = "2.61.0"
  access_key = "<AWS_ACCESS_KEY_ID>"
  secret_key = "<AWS_SECRET_KEY_ID>"
  region = "us-east-1"
}

data "http" "terra-client-ip" {
  url = "http://ipv4.icanhazip.com"
}

##### Use Default AWS VPC
data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_subnet" "pub_main_a" {
  id = var.subnet_a_id
}

data "aws_subnet" "pub_main_b" {
  id = var.subnet_b_id
}

data "aws_subnet" "pub_main_c" {
  id = var.subnet_c_id
}

##### Create SG
# ALB Security group
# This is the group you need to edit if you want to restrict access to your application
resource "aws_security_group" "ssh" {
  name        = "SSH"
  description = "SSH Port"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["${chomp(data.http.terra-client-ip.body)}/32"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "lb" {
  name        = "ECS-Ingress-ALB-SG"
  description = "Controls access to the ECS ALB"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "http" {
  name        = "Plain-HTTP"
  description = "HTTP Access Allowed"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


##### Create Load Balancer
resource "aws_alb" "main" {
  name            = "limon-ecs-alb-dev"
  subnets         = [data.aws_subnet.pub_main_a.id, data.aws_subnet.pub_main_b.id, data.aws_subnet.pub_main_c.id]
  security_groups = [aws_security_group.lb.id]
}

resource "aws_alb_target_group" "dev" {
  name                 = "limon-be-tg-dev"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = data.aws_vpc.main.id
  target_type          = "ip"
  deregistration_delay = 60

  health_check {
    path                = "/api/greet?name=Limon"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.main.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.main.id
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate
  
  default_action {
    target_group_arn = aws_alb_target_group.dev.arn
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "main" {
  listener_arn = aws_alb_listener.https.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.dev.arn
  }

  condition {
    host_header {
      values = ["apidemo.limonhost.net"]
    }
  }
}

# Create Task Execution Role
resource "aws_iam_role" "ecs_task_exec_role" {
  name = "limonTaskExecutionRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "task-exec-attach" {
  role       = aws_iam_role.ecs_task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

##### Create ECS Cluster
resource "aws_ecs_cluster" "main" {
  name               = "limonhost-dev-fargate-cluster"
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "limon-api" {
  family                   = "dev-limon-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_exec_role.arn
  cpu                      = 256
  memory                   = 512

  container_definitions = <<DEFINITION
[
  {
    "cpu": 256,
    "image": "753107444304.dkr.ecr.eu-central-1.amazonaws.com/limonultation:0.1",
    "memory": 512,
    "name": "dev-limon-api",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": 8080,
        "hostPort": 8080
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "dev-limon-fargate-logs",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "limon-api"
      }
    },
    "environment" : [
      {"name": "ENV_PARAMETRESI_1", "value": "Merhaba"},
      {"name": "ENV_PARAMETRESI_2", "value": "AWS"}
    ]
  }
]
DEFINITION
}

resource "aws_ecs_service" "limon-api" {
  name                              = "dev-limon-api-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.limon-api.arn
  desired_count                     = 1
  platform_version                  = "1.4.0"
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 10

  network_configuration {
    security_groups  = [aws_security_group.http.id]
    subnets          = [data.aws_subnet.pub_main_a.id, data.aws_subnet.pub_main_b.id, data.aws_subnet.pub_main_c.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.dev.id
    container_name   = "dev-limon-api"
    container_port   = 8080
  }
  
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_alb_listener.https]
}

##### Auto Scaling
resource "aws_appautoscaling_target" "limon_target" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.limon-api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "limon_scaling_policy" {
  name               = "scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.limon_target.resource_id
  scalable_dimension = aws_appautoscaling_target.limon_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.limon_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 50
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

# Create CodeBuild Service Role
resource "aws_iam_policy" "codebuild_perms" {
  name        = "codeBuildPermissionPolicy"
  path        = "/"
  description = "Main policy that CodeBuild uses"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "codebuild:CreateReportGroup",
        "codebuild:CreateReport",
        "codebuild:UpdateReport",
        "codebuild:BatchPutTestCases"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "codebuild_svc_role" {
  name = "codeBuildServiceRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "codebuild_s3_attach" {
  role       = aws_iam_role.codebuild_svc_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr_attach" {
  role       = aws_iam_role.codebuild_svc_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "codebuild_ecs_attach" {
  role       = aws_iam_role.codebuild_svc_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_main_attach" {
  role       = aws_iam_role.codebuild_svc_role.name
  policy_arn = aws_iam_policy.codebuild_perms.arn
}

##### CodeBuild Stuff
##### Core
resource "aws_codebuild_project" "limonultation" {
  name           = "limon-api-cicd"
  description    = "limon-api build and ship project"
  build_timeout  = "30"
  queued_timeout = "480"
  service_role   = aws_iam_role.codebuild_svc_role.arn
  source_version = "develop"

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:4.0-20.08.14"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  
    environment_variable {
      name  = "ENV"
      value = "dev"
    }

    environment_variable {
      name  = "APP"
      value = "limon-api"
    }

    environment_variable {
      name  = "CLUSTER_NAME"
      value = aws_ecs_cluster.main.name
    }
  }

  source {
    type                = "GITHUB"
    location            = "https://github.com/LimonCloud/fargate-demo-source"
    git_clone_depth     = 1
    report_build_status = true

    git_submodules_config {
      fetch_submodules = false
    }
  }
}