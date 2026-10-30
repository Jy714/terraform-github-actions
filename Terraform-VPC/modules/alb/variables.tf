variable "sg_id"{
    description = "Security Group ID for application load balancer"
    type = string
}

variable "subnets_id"{
    description = "subnets id for application load balancer"
    type = list(string)
}

variable "vpc_id"{
    description = "VPC Id"
    type = string
}

variable "instances" {
    description = "Instances id"
    type = list(string)
}