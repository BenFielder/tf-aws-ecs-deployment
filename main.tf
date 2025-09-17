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
  public_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

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
  subnets = module.vpc.public_subnets
  target_groups = {
      bfielder-instance = {
      name_prefix      = "h1"
      protocol         = "HTTP"
      port             = 80
      target_type      = "ip"
      create_attachment = false
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
module "ecs-security-group" {
  depends_on = [module.vpc]
  source = "terraform-aws-modules/security-group/aws"
  name = "bfielder-test-sg-ecs-deployment"
  vpc_id = module.vpc.vpc_id

  ingress_with_source_security_group_id = [{
    source_security_group_id = module.alb-security-group.security_group_id
    rule = "http-80-tcp"
    }]

}

module "alb-security-group" {
  depends_on = [module.vpc]
  source = "terraform-aws-modules/security-group/aws"
  name = "bfielder-test-sg-alb-deployment"
  vpc_id = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules = ["http-80-tcp"]
  egress_rules = ["all-all"]
  
}



module "ecs" {
  depends_on = [module.ecs-security-group]
  source = "terraform-aws-modules/ecs/aws"
  
  version = "6.3.0"

  cluster_name = "ecs-test-cluster-bfielder"

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

        ecs-sample = {
          cpu       = 512
          memory    = 1024
          essential = true
          image     = "public.ecr.aws/nginx/nginx:stable-perl"
          portMappings = [
            {
              name          = "ecs-sample"
              containerPort = 80
              protocol      = "tcp"
            }
          ]
          
          readonlyRootFilesystem = false

          enable_cloudwatch_logging = false
          memoryReservation = 100
        }
        logConfiguration = {
            logDriver = "awslogs"
              options = {
                Name                    = "awslogs"
                region                  = "eu-west-2"
              }
          }

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
          referenced_security_group_id = module.ecs-security-group.security_group_id
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

