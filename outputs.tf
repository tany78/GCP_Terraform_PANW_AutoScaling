output "vpc_name" {
  description = "Base name prefix used for VPCs"
  value       = var.vpc_name
}

output "vpc_names" {
  description = "Names of the management, untrust, and trust VPCs"
  value = {
    mgmt   = google_compute_network.vpc_mgmt.name
    untrust = google_compute_network.vpc_untrust.name
    trust  = google_compute_network.vpc_trust.name
  }
}

output "subnets" {
  description = "Subnets created in the VPC"
  value = {
    mgmt   = google_compute_subnetwork.mgmt.ip_cidr_range
    public = google_compute_subnetwork.public.ip_cidr_range
    private = google_compute_subnetwork.private.ip_cidr_range
  }
}

output "ingress_lb_ip" {
  description = "Public IP of the external Network Load Balancer"
  value       = google_compute_address.ingress_ip.address
}

output "egress_ilb_ip" {
  description = "Internal IP of the ILB next hop in the private subnet"
  value       = google_compute_forwarding_rule.egress_ilb.ip_address
}

# Bootstrap Module Outputs
output "bootstrap_bucket_name" {
  description = "Name of the bootstrap GCS bucket"
  value       = var.enable_bootstrap ? module.bootstrap[0].bucket_name : null
}

output "bootstrap_bucket_url" {
  description = "URL of the bootstrap GCS bucket"
  value       = var.enable_bootstrap ? format("gs://%s", module.bootstrap[0].bucket_name) : null
}

# Autoscaling Module Outputs
output "autoscale_instance_group_id" {
  description = "Instance group ID from the autoscaling module"
  value       = module.autoscale.regional_instance_group_id
}

output "autoscale_instance_group_manager" {
  description = "Instance group manager from the autoscaling module"
  value       = null
}

output "autoscale_delicensing_topic" {
  description = "Pub/Sub topic for delicensing (if enabled)"
  value       = (var.enable_delicensing && can(module.autoscale.delicensing_pubsub_topic)) ? module.autoscale.delicensing_pubsub_topic : null
}

# Panorama Module Outputs
output "panorama_public_ip" {
  description = "Public IP address of Panorama"
  value       = var.enable_panorama ? module.panorama[0].panorama_public_ip : null
}

output "panorama_private_ip" {
  description = "Private IP address of Panorama"
  value       = var.enable_panorama ? module.panorama[0].panorama_private_ip : null
}

output "panorama_instance_name" {
  description = "Instance name of Panorama"
  value       = null
}

# IAM Service Account Outputs
output "service_account_email" {
  description = "Email address of the created service account"
  value       = module.iam_service_account.email
}

output "service_account_roles" {
  description = "List of roles assigned to the service account"
  value       = var.service_account_roles
}