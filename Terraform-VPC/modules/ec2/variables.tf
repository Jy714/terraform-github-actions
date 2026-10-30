variable "sg_id"{
    description = "Security group id"
    type = string
}

variable "subnets" {
    description = "Subnets for EC2"
    type = list(string)
}

variable "ec2_names"{
    description = "EC2 names"
    type = list(string)
    default = [ "WebServer1", "WebServer2" ]
}