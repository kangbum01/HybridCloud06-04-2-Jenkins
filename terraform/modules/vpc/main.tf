####################################
# 1. VPC 생성
# 1-1. 보안 그룹 생성
# 2. IGW 생성 및 연결
# 3-1. PubSN 생성
# 3-2. PriSN 생성
# 4-1. PubSN-RT 생성 및 연결
# 4-2. PriSN-RT 생성 및 연결
####################################



# 1. VPC 생성
resource "aws_vpc" "myVPC" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = var.name
  }
}

# 2-1. IGW 생성 및 연결
resource "aws_internet_gateway" "myIGW" {
  vpc_id = aws_vpc.myVPC.id
  tags = {
    Name = "${var.name}-igw"
  }
}



# 3-1. PubSN 생성 (4개)
resource "aws_subnet" "myPubSN" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.myVPC.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}


# 3-2. PriSN 생성 (4개)
resource "aws_subnet" "myPriSN" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.myVPC.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index] # ✅ 같은 인덱스로 같은 AZ

  tags = {
    Name = "${var.name}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}



# 2-2. EIP 생성 과 NAT 생성 및 연결
resource "aws_eip" "myNATEIP" {
  count = 2
  domain = "vpc"
  tags = {
    Name = "${var.name}-nat-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "myNAT" {
  count = 2
  allocation_id = aws_eip.myNATEIP[count.index].id
  subnet_id     = aws_subnet.myPubSN[count.index == 0 ? 0 : 2].id  # 0->2a, 1->2c

  tags = {
    Name = "${var.name}-nat-${count.index == 0 ? "2a" : "2c"}"
  }
  depends_on = [aws_internet_gateway.myIGW]
}

# 4-1. PubSN-RT 생성 및 연결
resource "aws_route_table" "myPubRT" {
  vpc_id = aws_vpc.myVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myIGW.id
  }

  tags = {
    Name = "${var.name}-PubSN-RT"
  }
}

resource "aws_route_table_association" "myPubRTassoc" {
  count     = length(aws_subnet.myPubSN)
  subnet_id = aws_subnet.myPubSN[count.index].id
  route_table_id = aws_route_table.myPubRT.id
}

# 4-2. PriSN-RT 생성 및 연결(2개 -> 어느 Nat gateway로 나갈 지 정해준다)
resource "aws_route_table" "myPriRT" {
  count = 2
  vpc_id = aws_vpc.myVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.myNAT[count.index].id
  }

  tags = {
    Name = "${var.name}-PriSN-RT-${count.index}"
  }
}

# 인덱스 0,1은 RT0 / 2,3은 RT1
resource "aws_route_table_association" "myPriRTassoc" {
  count     = length(aws_subnet.myPriSN)
  subnet_id = aws_subnet.myPriSN[count.index].id
  route_table_id = aws_route_table.myPriRT[count.index < 2 ? 0 : 1].id
}



