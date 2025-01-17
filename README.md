hcl
# Terraform Block
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# AWS Provider Configuration
# Sets the AWS region where resources will be created
provider "aws" {
  region = "us-east-1"
}

# Kubernetes Provider Configuration
# Allows Terraform to interact with the Kubernetes API of the EKS cluster
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# VPC Configuration
# Defines the Virtual Private Cloud for EKS
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "eks-vpc"
  }
}

# Internet Gateway for the VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "eks-igw"
  }
}

# Public Subnets for EKS Node Group
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = "us-east-1${element(["a", "b"], count.index)}"
  map_public_ip_on_launch = true
  tags = {
    Name = "eks-public-subnet-${count.index}"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "eks-public-rt"
  }
}

# Association between Route Table and Public Subnets
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# EKS Cluster IAM Role
# Role needed for the EKS service to manage cluster resources
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS Managed Policy to EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = aws_subnet.public[*].id
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
  ]
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_nodes" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS Managed Policies to EKS Nodes Role
resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "eks-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t2.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# EKS Cluster Auth Data
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# Deploy Zomato Clone Application
resource "kubernetes_deployment" "zomato_clone" {
  metadata {
    name = "zomato-clone"
    labels = {
      app = "zomato-clone"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "zomato-clone"
      }
    }
    template {
      metadata {
        labels = {
          app = "zomato-clone"
        }
      }
      spec {
        container {
          image = "iamtejas23/zomato-clone:latest"
          name  = "zomato-clone-container"
          port {
            container_port = 80 # Assuming the application listens on port 80, adjust if different
          }
        }
      }
    }
  }
}

# Expose the Zomato Clone Application
resource "kubernetes_service" "zomato_clone" {
  metadata {
    name = "zomato-clone-service"
  }
  spec {
    selector = {
      app = kubernetes_deployment.zomato_clone.metadata[0].labels.app
    }
    port {
      port        = 80
      target_port = 80 # Match this with the container_port in the deployment
    }
    type = "LoadBalancer"
  }
}

# Output the LoadBalancer's external IP
output "zomato_clone_lb_endpoint" {
  value = kubernetes_service.zomato_clone.status[0].load_balancer[0].ingress[0].hostname
}

# Output Cluster Endpoint
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

# Output Cluster Name
output "cluster_name" {
  value = aws_eks_cluster.main.name
}

Documentation:
Terraform Block: Specifies the required providers and versions for AWS and Kubernetes resources.
Provider Configuration: Configures Terraform to use AWS and Kubernetes APIs.
Network Resources: Sets up the VPC, Internet Gateway, Subnets, and Route Tables necessary for the EKS cluster.
IAM Roles and Policies: Defines roles for the EKS cluster and node groups, attaching necessary AWS managed policies.
EKS Cluster: Creates the EKS cluster within the specified VPC.
EKS Node Group: Configures a group of EC2 instances to act as worker nodes for the EKS cluster.
Cluster Authentication: Uses a data source to fetch authentication details for the Kubernetes provider.
Application Deployment: Deploys the zomato-clone application using Kubernetes resources (Deployment and Service).
Outputs: Provides endpoints and names for easy access post-deployment.
