variable "project_id" {
  description = "GCP project ID to deploy resources into"
  type        = string
  default     = "serene-tooling-473909-e9"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-south2"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "asia-south2-b"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "perimeter-vpc"
}

variable "public_subnet_cidr" {
  description = "CIDR range for the public (untrust) subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR range for the private (trust) subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "mgmt_subnet_cidr" {
  description = "CIDR range for the management subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "pa_image" {
  description = "Palo Alto VM-Series image self_link or family. Example: projects/paloaltonetworksgcp-public/global/images/family/vmseries-flex-byol"
  type        = string
  default     = "/projects/paloaltonetworksgcp-public/global/images/vmseries-flex-byol-1125"
}

variable "machine_type" {
  description = "Machine type for the firewall instances"
  type        = string
  default     = "n2-standard-4"
}


variable "ssh_source_ranges" {
  description = "Source CIDR ranges allowed to access management via SSH/HTTPS"
  type        = list(string)
  default     = ["49.204.149.8/32"]
}

variable "fw_health_check_port" {
  description = "TCP port used by LB health checks to reach the firewall"
  type        = number
  default     = 80
}

variable "ingress_lb_ports" {
  description = "Ports exposed on the external Network Load Balancer"
  type        = list(string)
  default     = ["80", "443"]
}

variable "min_replicas" {
  description = "Minimum number of firewall instances"
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum number of firewall instances"
  type        = number
  default     = 0
}

# Bootstrap Module Variables
variable "enable_bootstrap" {
  description = "Enable bootstrap module for VM-Series initial configuration"
  type        = bool
  default     = false
}

variable "bootstrap_files_dir" {
  description = "Local directory containing bootstrap files (config, content, license, software)"
  type        = string
  default     = "./bootstrap"
}

variable "bootstrap_files" {
  description = "Map of bootstrap files to upload. Key = local path, Value = remote path in bucket"
  type        = map(string)
  default     = {"./bootstrap/config/init-cfg.txt" = "config/init-cfg.txt", "./bootstrap/config/bootstrap.xml" = "config/bootstrap.xml"}  
}

# Autoscaling Module Variables
variable "enable_delicensing" {
  description = "Enable delicensing cloud function for automatic license cleanup"
  type        = bool
  default     = true
}

variable "autoscaler_metrics" {
  description = "Map of autoscaling metrics: each value is an object with at least `target` (number) and optional `type` (GAUGE | DELTA_PER_SECOND | DELTA_PER_MINUTE)."
  type        = map(any)
  default = {
    "compute.googleapis.com/instance/cpu/utilization" = {
      target = 0.6
      type   = "GAUGE"
    }
  }
}

variable "cooldown_period" {
  description = "Number of seconds autoscaler waits before collecting information from new VM-Series"
  type        = number
  default     = 60
}

variable "scale_in_control_time_window_sec" {
  description = "How far (in seconds) autoscaling looks into the past when scaling down"
  type        = number
  default     = 600
}

variable "scale_in_control_replicas_fixed" {
  description = "Fixed number of VM-Series instances that can be killed within scale-in time window"
  type        = number
  default     = 1
}

# Panorama Module Variables
variable "enable_panorama" {
  description = "Enable Panorama management server deployment"
  type        = bool
  default     = true
}

variable "panorama_ssh_keys" {
  description = "SSH public keys for Panorama access (format: 'admin:ssh-rsa AAAAB3...')"
  type        = string
  default     = "<Put_Your_Own_Ssh_Key>"
}

variable "panorama_machine_type" {
  description = "Machine type for Panorama instance"
  type        = string
  default     = "n1-standard-4"
}

variable "panorama_version" {
  description = "Panorama version to deploy (public image name)"
  type        = string
  default     = "panorama-1126"
}

# Switch to using a custom image name for Panorama
#variable "custom_image" {
#  description = "Custom image name or self_link for Panorama"
#  type        = string
#  default     = "panw-panorama2-vm-1126"
#}

variable "panorama_log_disks" {
  description = "List of additional disks for Panorama logging"
  type = list(object({
    name = string
    type = string
    size = string
  }))
  default = []
}

# Panorama management IP configuration
variable "panorama_mgmt_private_ip" {
  description = "Static private IP for Panorama management NIC (in mgmt subnet). Set to null for dynamic."
  type        = string
  default     = "10.0.2.10"
}

variable "panorama_create_public_ip" {
  description = "Whether to create a public IP for Panorama management access"
  type        = bool
  default     = true
}

# Bootstrap registration variables
variable "pan_vm_auth_key" {
  description = "Panorama VM auth key used by firewalls to auto-register during bootstrap"
  type        = string
  default     = ""
}

# SSH keys for VM-Series firewalls (autoscale)
variable "fw_ssh_keys" {
  description = "SSH public keys for VM-Series firewall admin access (format: 'admin:ssh-rsa AAAAB3...')"
  type        = string
  default     = "<Put_Your_Own_Ssh_Key>"
}

######################################################
# Alternate bootstrap via instance metadata parameters #
######################################################

variable "panorama_server" {
  description = "Panorama server IP or hostname for VM-Series registration (metadata key: panorama-server)"
  type        = string
  default     = "10.0.2.10"
}

variable "vm_auth_key" {
  description = "Panorama VM Auth Key used by VM-Series to auto-register (metadata key: vm-auth-key)"
  type        = string
  default     = "<Generate VM Auth Key on Panorama>"
}

variable "auth_key" {
  description = "Panorama Licensing plugin key for VM-Series (metadata key: auth-key)"
  type        = string
  default     = "<Generate Auth Key on Panorama if going with Licensing Plugin Configuration>"
}

variable "authcodes" {
  description = "BYOL licensing auth codes (comma-separated) (metadata key: authcodes)"
  type        = string
  default     = "<Firewall Licensing Auth Code from CSP Portal>"
}

variable "tplname" {
  description = "Panorama Template name to join (metadata key: tplname)"
  type        = string
  default     = "GCP_MIG_Stack"
}

variable "dgname" {
  description = "Panorama Device Group name to join (metadata key: dgname)"
  type        = string
  default     = "GCP_MIG_DG"
}

variable "dns_primary" {
  description = "Primary DNS server (metadata key: dns-primary)"
  type        = string
  default     = "8.8.8.8"
}

variable "dns_secondary" {
  description = "Secondary DNS server (metadata key: dns-secondary)"
  type        = string
  default     = "8.8.4.4"
}

variable "dhcp_send_hostname" {
  description = "Whether to send hostname via DHCP on mgmt (metadata key: dhcp-send-hostname)"
  type        = string
  default     = "yes"
}

variable "dhcp_send_client_id" {
  description = "Whether to send client-id via DHCP on mgmt (metadata key: dhcp-send-client-id)"
  type        = string
  default     = "yes"
}

variable "plugin_op_commands" {
  description = "Optional plugin operational commands (metadata key: plugin-op-commands)"
  type        = string
  default     = "panorama-licensing-mode-on"
}

variable "vmseries_pin_id" {
  description = "Auto-registration pin ID (metadata key: vm-series-auto-registration-pin-id)"
  type        = string
  default     = "<PIN ID for certificate download and registration from CSP Portal>"
}

variable "vmseries_pin_value" {
  description = "Auto-registration pin value (metadata key: vm-series-auto-registration-pin-value)"
  type        = string
  default     = "<PIN Value for certificate download and registration from CSP Portal>"
}

variable "mgmt_type" {
  description = "Management interface address type: dhcp-client or static (metadata key: type)"
  type        = string
  default     = "dhcp-client"
}

############################
# IAM Service Account        #
############################

variable "service_account_id" {
  description = "Service account ID for VM-Series and Panorama instances"
  type        = string
  default     = "vmseries-sa"
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "VM-Series Service Account"
}

variable "service_account_description" {
  description = "Description for the service account"
  type        = string
  default     = "Service account for VM-Series firewall and Panorama instances with enhanced firewall-specific roles"
}

variable "service_account_roles" {
  description = "List of IAM roles to assign to the service account"
  type        = list(string)
  default = [
    "roles/compute.instanceAdmin.v1",
    "roles/compute.networkViewer",
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer"
  ]
}