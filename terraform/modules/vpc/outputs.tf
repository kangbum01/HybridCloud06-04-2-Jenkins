output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.myVPC.id
}

output "vpc_cidr" {
  description = "VPC CIDR"
  value       = aws_vpc.myVPC.cidr_block
}

output "igw_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.myIGW.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [for s in aws_subnet.myPubSN : s.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = [for s in aws_subnet.myPriSN : s.id]
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.myPubRT.id
}

output "private_route_table_ids" {
  description = "Private route table ID (one per NAT group)"
  value       = aws_route_table.myPriRT[*].id
}

output "nat_gateway_ids" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.myNAT[*].id
}

output "nat_eip_public_ips" {
  description = "NAT EIP public IP"
  value       = aws_eip.myNATEIP[*].public_ip
}

output "nat_eip_allocation_ids" {
  description = "NAT EIP allocation id"
  value       = aws_eip.myNATEIP[*].allocation_id
}

output "public_subnet_cidrs"  { 
  value = aws_subnet.myPubSN[*].cidr_block 
}

output "private_subnet_cidrs" { 
  value = aws_subnet.myPriSN[*].cidr_block 
}
