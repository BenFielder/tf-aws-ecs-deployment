provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
    state = "available"
}

locals {
  name = "${basename(path.cwd)}-${var.app_name}"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
  
  container_name = "bfielder-container-test"
  container_port = 3000
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"

  cidr = "10.0.0.0/16"
  name = "bfielder-test-vpc"

  azs = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets = ["10.0.0.0/24"]

  enable_nat_gateway = true
  enable_dns_hostnames = true

}



#Load balancer
module "alb" {
  depends_on = [module.vpc]
  source = "terraform-aws-modules/alb/aws"
  version = "9.17.0"

  name = "bfielder-alb-test"
  vpc_id = module.vpc.vpc_id
  subnets = [module.vpc.private_subnets[0], module.vpc.public_subnets[0]] #Needs rethinking 
  target_groups = {
      bfielder-instance = {
      target_id        = ""
      name_prefix      = "h1"
      protocol         = "HTTP"
      port             = 80
      target_type      = "ip"
    }
  }

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "10.0.0.0/16"
    }
  }


}

#Security Group


module "ecs" {
  source = "terraform-aws-modules/ecs/aws"
  
  version = "6.3.0"

  cluster_name = "ecs-test-cluster-bfielder"

  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = "/aws/ecs/aws-ec2"
      }
    }
  }

  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 50
      base   = 20
    }
    FARGATE_SPOT = {
      weight = 50
    }
  }

  services = {
    ecsdemo-frontend = {
      cpu    = 1024
      memory = 4096

      container_definitions = {

        fluent-bit = {
          cpu       = 512
          memory    = 1024
          essential = true
          image     = "906394416424.dkr.ecr.us-west-2.amazonaws.com/aws-for-fluent-bit:stable"
          firelensConfiguration = {
            type = "fluentbit"
          }
          memoryReservation = 50
        }

        ecs-sample = {
          cpu       = 512
          memory    = 1024
          essential = true
          image     = "public.ecr.aws/aws-containers/ecsdemo-frontend:776fd50"
          portMappings = [
            {
              name          = "ecs-sample"
              containerPort = 80
              protocol      = "tcp"
            }
          ]

          # Example image used requires access to write to root filesystem
          readonlyRootFilesystem = false

          dependsOn = [{
            containerName = "fluent-bit"
            condition     = "START"
          }]

          enable_cloudwatch_logging = false
          logConfiguration = {
            logDriver = "awsfirelens"
            options = {
              Name                    = "firehose"
              region                  = "eu-west-1"
              delivery_stream         = "my-stream"
              log-driver-buffer-limit = "2097152"
            }
          }
          memoryReservation = 100
        }
      }

      service_connect_configuration = {
        namespace = "bfielder-test-example"
        service = [{
          client_alias = {
            port     = 80
            dns_name = "ecs-sample"
          }
          port_name      = "ecs-sample"
          discovery_name = "ecs-sample"
        }]
      }

      load_balancer = {
        service = {
          target_group_arn = module.alb.target_groups["bfielder-instance"].arn
          container_name   = "bfielder-ecs-test-lb"
          container_port   = 80
        }
      }

      subnet_ids = module.vpc.private_subnets
      security_group_ingress_rules = {
        alb_3000 = {
          description                  = "Service port"
          from_port                    = local.container_port
          ip_protocol                  = "tcp"
          referenced_security_group_id = "sg-12345678"
        }
      }
      security_group_egress_rules = {
        all = {
          ip_protocol = "-1"
          cidr_ipv4   = "0.0.0.0/0"
        }
      }
    }
  }

  tags = {
    Environment = "Dev"
    Project     = "Example"
  }
}