# Provisions a spot EC2 instance with 
# Zone for AMI is us-west-2

provider "aws" {
  region = "us-west-2"
}

resource "aws_vpc" "test-env" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "subnet-uno" {
  # creates a subnet
  cidr_block        = "${cidrsubnet(aws_vpc.test-env.cidr_block, 3, 1)}"
  vpc_id            = "${aws_vpc.test-env.id}"
  availability_zone = "us-west-2a"
}

resource "aws_security_group" "ingress-ssh-test" {
  name   = "allow-ssh-sg"
  vpc_id = "${aws_vpc.test-env.id}"

  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]

    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ingress-http-test" {
  name   = "allow-http-sg"
  vpc_id = "${aws_vpc.test-env.id}"

  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]

    from_port = 80
    to_port   = 81
    protocol  = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ingress-https-test" {
  name   = "allow-https-sg"
  vpc_id = "${aws_vpc.test-env.id}"

  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]

    from_port = 443
    to_port   = 443
    protocol  = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "test-env-gw" {
  vpc_id = "${aws_vpc.test-env.id}"
}

resource "aws_route_table" "route-table-test-env" {
  vpc_id = "${aws_vpc.test-env.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.test-env-gw.id}"
  }
}

resource "aws_route_table_association" "subnet-association" {
  subnet_id      = "${aws_subnet.subnet-uno.id}"
  route_table_id = "${aws_route_table.route-table-test-env.id}"
}

resource "aws_spot_instance_request" "test_worker" {
  ami                    = "ami-08e2c1a8d17c2fe17" 
  spot_price             = "0.09" # não passou com 0.009
  instance_type          = "t2.micro"
  spot_type              = "one-time"
  block_duration_minutes = "0"
  wait_for_fulfillment   = "true"
  key_name               = "key-maio-25-2024"  
  security_groups = ["${aws_security_group.ingress-ssh-test.id}", "${aws_security_group.ingress-http-test.id}", "${aws_security_group.ingress-https-test.id}"]
  subnet_id = "${aws_subnet.subnet-uno.id}"
  
  user_data = <<EOF
#!/bin/bash

#### Executando Instalando PHP

sudo apt update && apt upgrade -y
sudo apt -y install software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt install php8.2 -y

# 

curl -sS https://getcomposer.org/installer | php 
sudo mv composer.phar /usr/local/bin/composer 

sudo apt install php libapache2-mod-php php-mbstring php-cli php-bcmath php-json php-xml php-zip php-common php-tokenizer php-mysql -y
sudo apt install unzip -y
sudo apt install sqlite3 -y
sudo apt install php8.2-sqlite3 -y

##### Obtemos o projeto pronto

cd /var/www/html
alvo="exemplo_laravel.zip"
wget https://march-2023-ia-eggs.s3.us-west-2.amazonaws.com/$alvo
unzip $alvo

pasta="exemplo_laravel"
mv $pasta/* .
mv $pasta/.* .
sudo rm -r $pasta $alvo

sudo chmod o+w ./storage/ -R
sudo chmod o+w ./database/database.sqlite -R

##### Configurar APACHE

wget https://march-2023-ia-eggs.s3.us-west-2.amazonaws.com/laravel.conf
cp laravel.conf /etc/apache2/sites-available/
sudo a2ensite laravel.conf 
sudo a2dissite 000-default.conf
sudo a2enmod rewrite 
sudo systemctl restart apache2 

composer install --no-dev --optimize-autoloader 
php artisan key:generate

EOF
}

resource "time_sleep" "wait_60_seconds" {
  depends_on = [aws_spot_instance_request.test_worker]
  create_duration = "400s"
}

resource "aws_eip" "ip-test-env" {
  instance = "${aws_spot_instance_request.test_worker.spot_instance_id}"
  domain   = "vpc"
  depends_on = [time_sleep.wait_60_seconds]
}
