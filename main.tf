#1. Tell Terraform to include the hcloud provider
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.45.0"
    }
  }
}

#2. Declare the hcloud_token variable from .tfvars
variable "hcloud_token" {
  sensitive = true 
}

#3. Configure the Hetzner Cloud Provider with your token
provider "hcloud" {
  token = var.hcloud_token
}

#4. Creating a Private Network
resource "hcloud_network" "private_network" {
  name     = "kubernetes-cluster"
  ip_range = "10.0.0.0/16"
}

#4.1. Creating a Network Subnet
resource "hcloud_network_subnet" "private_network_subnet" {
  type         = "cloud"
  network_id   = hcloud_network.private_network.id
  network_zone = "eu-central"
  ip_range     = "10.0.0.0/24"
}

#5. Creating a Bastion Node
resource "hcloud_server" "bastion-node" {
  name        = "bastion-node"
  image       = "ubuntu-22.04"
  server_type = "cax11"
  location    = "fsn1"
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.0.2"
  }
  user_data = file("${path.module}/cloud-init-bastion.yaml")

  depends_on = [hcloud_network_subnet.private_network_subnet]
}

#6. Creating a Network Route
resource "hcloud_network_route" "my_route" {
  network_id  = hcloud_network.private_network.id
  destination = "0.0.0.0/0"
  gateway     = "10.0.0.2"
}

#7. Creating a Master Node 
resource "hcloud_server" "master-node" {
  name        = "master-node"
  image       = "ubuntu-22.04"
  server_type = "cax11"
  location    = "fsn1"
  public_net {
    ipv4_enabled = false 
    ipv6_enabled = false
  }
  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.0.3"
  }
  user_data = file("${path.module}/cloud-init-master.yaml")

  depends_on = [
    hcloud_network_subnet.private_network_subnet,
    hcloud_server.bastion-node
  ]
}

#8. Adding a Delay Resource- dummy resource that introduces a 2-minute delay after the master-node creation.
resource "null_resource" "delay" {
  # Use count to ensure it runs once
  count = 1 

  provisioner "local-exec" {
    command = "sleep 160"  # Sleep for 2 minutes
  }

  # Run this null_resource after the master-node is created
  depends_on = [hcloud_server.master-node]
}

#9. Creating Worker Nodes
resource "hcloud_server" "worker-nodes" {
  count = 2 

  # The name will be worker-node-0, worker-node-1, worker-node-2...
  name        = "worker-node-${count.index}"
  image       = "ubuntu-22.04"
  server_type = "cax11"
  location    = "fsn1"
  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }
  network {
    network_id = hcloud_network.private_network.id
  }

  user_data = file("${path.module}/cloud-init-worker.yaml")

  depends_on = [
    hcloud_network_subnet.private_network_subnet,
    hcloud_server.bastion-node,
    hcloud_server.master-node,
    null_resource.delay  # Ensure worker node creation waits for the delay
  ]
}

#10. Creating a Private Load Balancer

resource "hcloud_load_balancer" "private_load_balancer" {
  name               = "private-lb"
  load_balancer_type = "lb11"
  location           = "fsn1"
}

#10.1. Adding the Private Load Balancer to the Network
resource "hcloud_load_balancer_network" "private_load_balancer_network" {
  load_balancer_id = hcloud_load_balancer.private_load_balancer.id
  network_id       = hcloud_network.private_network.id
  ip               = "10.0.0.4"
  enable_public_interface = false

  depends_on = [hcloud_network_subnet.private_network_subnet]
}

#10.2. Adding Targets to the Private Load Balancer
resource "hcloud_load_balancer_target" "private_load_balancer_target" {
  count            = length(hcloud_server.worker-nodes)
  type             = "server"
  load_balancer_id = hcloud_load_balancer.private_load_balancer.id
  server_id        = hcloud_server.worker-nodes[count.index].id
  use_private_ip   = true
}

#10.3. Configuring the Private Load Balancer Service
resource "hcloud_load_balancer_service" "private_load_balancer_service" {
  load_balancer_id = hcloud_load_balancer.private_load_balancer.id
  protocol         = "http"
  listen_port      = 80
  destination_port = 30080

  http {
    sticky_sessions = true
    cookie_name     = "EXAMPLE_STICKY"
  }

  health_check {
    protocol = "http"
    port     = 80
    interval = 30    # Increased interval
    timeout  = 10    # Increased timeout

    http {
      path         = "/"
      response     = "OK"
      tls          = false
      status_codes = ["200"]
    }
  }
}

#11. Creating a Public Load Balancer
resource "hcloud_load_balancer" "public_load_balancer" {
  name               = "public-lb"
  load_balancer_type = "lb11"
  location           = "fsn1"
}

#11.1. Adding the Public Load Balancer to the Network
resource "hcloud_load_balancer_network" "public_load_balancer_network" {
  load_balancer_id = hcloud_load_balancer.public_load_balancer.id
  network_id       = hcloud_network.private_network.id
  ip               = "10.0.0.6"
  enable_public_interface = true

  depends_on = [hcloud_network_subnet.private_network_subnet]
}

#11.2. Adding Targets to the Public Load Balancer
resource "hcloud_load_balancer_target" "public_load_balancer_target" {
  count            = length(hcloud_server.worker-nodes)
  type             = "server"
  load_balancer_id = hcloud_load_balancer.public_load_balancer.id
  server_id        = hcloud_server.worker-nodes[count.index].id
  use_private_ip   = true
}

#11.3. Configuring the Public Load Balancer Service
resource "hcloud_load_balancer_service" "public_load_balancer_service" {
  load_balancer_id = hcloud_load_balancer.public_load_balancer.id
  protocol         = "http"
  listen_port      = 80
  destination_port = 30080

  http {
    sticky_sessions = true
    cookie_name     = "EXAMPLE_STICKY"
  }

  health_check {
    protocol = "http"
    port     = 80 
    interval = 20    
    timeout  = 10   

    http {
      path         = "/"
      status_codes = ["200"]
    }
  }
}

