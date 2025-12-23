/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Defines the VPC, subnets, gateways, and routing tables.
 * Scope        : Module (Network)
 */

/*
 * ----------------------
 * VPC & Internet Gateway
 * ----------------------
 * The Virtual Private Cloud (VPC) serves as the isolated network environment
 * for the Kubernetes cluster. DNS hostnames and support are enabled to
 * facilitate internal service discovery and node registration within the cluster.
 */
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # Required for K8s nodes to register with their private DNS names
  enable_dns_support   = true # Required for the VPC to resolve DNS names

  tags = {
    Name = "${var.vpc_resource_prefix}-vpc"
  }
}

/*
 * The Internet Gateway provides a direct path for outbound internet traffic
 * from public subnets and serves as the entry point for external traffic
 * destined for public-facing load balancers.
 */
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_resource_prefix}-igw"
  }
}

/*
 * ---------------------------------
 * Default Security Group (Lockdown)
 * ---------------------------------
 * To adhere to security best practices (e.g., CIS Benchmarks), the default
 * security group is neutralized. This prevents unintended access by ensuring
 * that resources without an explicitly assigned security group do not inherit
 * permissive default rules.
 */
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_resource_prefix}-default-sg"
  }
}

/*
 * ------------------------------
 * Default Route Table (Lockdown)
 * ------------------------------
 * To adhere to security best practices (e.g., CIS Benchmarks), the default
 * route table is adopted and locked down. This ensures that any subnets not
 * explicitly associated with a route table do not have accidental internet access.
 */
resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.main.default_route_table_id
  route                  = []
  propagating_vgws       = []

  tags = {
    Name = "${var.vpc_resource_prefix}-default-rt"
  }
}

/*
 * ------------------------
 * Public Subnets & Routing
 * ------------------------
 * Public subnets are provisioned across multiple Availability Zones to support
 * high availability. Instances launched here receive public IP addresses
 * automatically. Tags include `kubernetes.io/role/elb` to allow the AWS Load
 * Balancer Controller to automatically discover these subnets for public Load
 * Balancer provisioning.
 */
resource "aws_subnet" "public" {
  count                   = length(var.vpc_public_subnets_cidr)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.vpc_public_subnets_cidr[count.index]
  availability_zone       = element(var.vpc_availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name                     = "${var.vpc_resource_prefix}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1" # Required for AWS Load Balancer Controller
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_resource_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.vpc_public_subnets_cidr)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

/*
 * ----------------------------------------------------------
 * NAT Gateways (One per Public Subnet for High Availability)
 * ----------------------------------------------------------
 * Network Address Translation (NAT) Gateways are deployed in each public subnet
 * to provide outbound internet connectivity for resources in private subnets.
 * This configuration ensures high availability; if one Availability Zone fails,
 * private subnets in other zones retain internet access via their respective
 * NAT Gateways.
 */
resource "aws_eip" "nat" {
  count  = length(var.vpc_public_subnets_cidr)
  domain = "vpc"

  tags = {
    Name = "${var.vpc_resource_prefix}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nat" {
  count         = length(var.vpc_public_subnets_cidr)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.vpc_resource_prefix}-nat-gw-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.igw] # Ensure IGW is created before NAT Gateway for proper routing
}

/*
 * -------------------------
 * Private Subnets & Routing
 * -------------------------
 * Private subnets host the Kubernetes worker nodes and control plane components,
 * isolating them from direct internet access. Outbound traffic is routed
 * through NAT Gateways. Tags include `kubernetes.io/role/internal-elb` for
 * internal Load Balancer discovery.
 */
resource "aws_subnet" "private" {
  count             = length(var.vpc_private_subnets_cidr)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.vpc_private_subnets_cidr[count.index]
  availability_zone = element(var.vpc_availability_zones, count.index)

  tags = {
    Name                              = "${var.vpc_resource_prefix}-private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1" # Required for internal Load Balancers
  }
}

resource "aws_route_table" "private" {
  count  = length(var.vpc_private_subnets_cidr)
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_resource_prefix}-private-rt-${count.index + 1}"
  }
}

resource "aws_route" "private_nat_access" {
  count                  = length(var.vpc_private_subnets_cidr)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.nat[*].id, count.index)
}

resource "aws_route_table_association" "private" {
  count          = length(var.vpc_private_subnets_cidr)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
