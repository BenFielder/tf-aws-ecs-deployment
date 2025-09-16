variable "aws_region" {
  description = "AWS Region to use"
  type        = string
  default     = "eu-west-2"
}

variable "container_image" {
  description = "Docker image for the container"
  type        = string
  default     = "nginx:latest"
}

variable "app_name" {
  description = "Name of the app"
  type        = string
  default     = "bfielder-test-app"
}

variable "container_port" {
  description = "Port number that the container will listen on"
  type        = number
  default     = 80
}

variable "vpc_cidr_range" {
  description = "CIDR Block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "desired_capacity" {
  description = "Desired number of running tasks"
  type        = number
  default     = 2
}