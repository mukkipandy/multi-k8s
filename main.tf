provider "aws" {
  region = "ap-south-1"
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach Required Policies to EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_role_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  ])
  
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = each.value
}

# IAM Role for EKS Worker Nodes
resource "aws_iam_role" "eks_worker_node_role" {
  name = "eks-worker-node-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach Required Policies to EKS Worker Node Role
resource "aws_iam_role_policy_attachment" "eks_worker_node_role_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicy"
  ])

  role       = aws_iam_role.eks_worker_node_role.name
  policy_arn = each.value
}

# VPC Configuration
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-south-1a", "ap-south-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
}

# EKS Cluster
resource "aws_eks_cluster" "eks" {
  name     = "multi-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = module.vpc.private_subnets
  }
}

# EKS Node Group
resource "aws_eks_node_group" "worker_nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "free-tier-nodes"
  node_role_arn   = aws_iam_role.eks_worker_node_role.arn

  subnet_ids        = module.vpc.private_subnets
  instance_types    = ["t3.medium"]
  
  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }
}

# EBS CSI Driver Addon
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "aws-ebs-csi-driver"
  resolve_conflicts = "OVERWRITE"
}

output "cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "node_group_role" {
  value = aws_iam_role.eks_worker_node_role.arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
