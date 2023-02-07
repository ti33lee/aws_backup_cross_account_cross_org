#creating dummy env for test - requires networking and rds

resource "aws_vpc" "main" {
cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "pvt-subnetA" {
vpc_id = "${aws_vpc.main.id}"
cidr_block = "10.0.1.0/24"
availability_zone = "eu-west-1a"
}

resource "aws_subnet" "pvt-subnetB" {
vpc_id = "${aws_vpc.main.id}"
cidr_block = "10.0.2.0/24"
availability_zone = "eu-west-1b"
}

resource "aws_db_subnet_group" "db-subnet" {
name = "db_subnet_group"
subnet_ids = ["${aws_subnet.pvt-subnetA.id}", "${aws_subnet.pvt-subnetB.id}"]
}

resource "aws_db_instance" "default" {
allocated_storage = 20
identifier = "testinstance"
storage_type = "gp2"
engine = "mysql"
engine_version = "5.7"
instance_class = "db.t2.micro"
db_name = "test"
username = "admin"
password = "Admin54132"
parameter_group_name = "default.mysql5.7"
skip_final_snapshot  =  true
db_subnet_group_name = "${aws_db_subnet_group.db-subnet.name}"
tags = {
    "awsBackup" = true
}

}