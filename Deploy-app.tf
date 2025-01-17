provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# ... (keep all existing AWS resources for EKS setup here)

# EKS Cluster Auth Data
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# Deploy the Zomato Clone Application
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
            container_port = 3000 # Assuming the application listens on port 80, adjust if different
          }
        }
      }
    }
  }
}

# Expose the Zomato Clone via a LoadBalancer service
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
      target_port = 3000 # Match this with the container_port in the deployment
    }
    type = "LoadBalancer"
  }
}

# Output the LoadBalancer's external IP
output "zomato_clone_lb_endpoint" {
  value = kubernetes_service.zomato_clone.status[0].load_balancer[0].ingress[0].hostname
}
