# private-k8s-cluster-hetzner
Terraform configuration for setting up a private Kubernetes cluster on Hetzner Cloud, featuring bastion hosts, private and public load balancers, and secure node access.
#### Infrastructure Overview

In this setup, I've configured a bastion node with access to the public network, accompanied by 1 master node and 2 worker nodes located in a private network. A NAT gateway on the bastion server facilitates connectivity from the private-network-only servers (master and worker nodes) to the public network by routing traffic through the bastion node, which acts as a NAT server with a public IP address. SSH access to the master and worker nodes is managed through the bastion node.

#### Kubernetes Setup with k3s

When provisioning nodes on Hetzner Cloud, you can specify cloud-init scripts (`cloud-init-bastion.yaml`, `cloud-init-master.yaml`, `cloud-init-worker.yaml`) to automate configuration tasks such as installing software like Kubernetes. In this case, we opt for k3s instead of traditional Kubernetes due to its lightweight nature and ease of management.

#### Configuration Steps

Before applying the configuration, ensure these edits are made:

1. Generate an SSH key for the worker nodes (a single key can be used for all workers).
2. Replace `<LOCALHOST_SSH_PUBLIC_KEY>` in `cloud-init-bastion.yaml` with the public SSH key of your local machine.
3. Replace `<WORKER_NODE_SSH_PUBLIC_KEY>` in `cloud-init-master.yaml` with the public SSH key of your worker node(s).
4. Replace `<WORKER_NODE_PRIVATE_SSH_KEY>` in `cloud-init-worker.yaml` with the private SSH key for your worker node(s) and optionally add `<LOCALHOST_SSH_PUBLIC_KEY>` for necessary operations.

#### Initialization and Deployment

To initialize the project and deploy your Kubernetes cluster:

1. Run `terraform init` to set up the project and download the required `hcloud` provider.
2. Execute `terraform apply -var-file .tfvars` to deploy the cluster, including network setup, routes, bastion node, master, and worker nodes.
3. Optionally, when you're finished with the cluster, destroy it using `terraform destroy -var-file .tfvars` to prevent unnecessary costs.

These steps streamline the setup and management of your Kubernetes infrastructure on Hetzner Cloud, leveraging Terraform and cloud-init for automation and configuration.
