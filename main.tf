############################
# Networking: VPCs & Subnets #
############################

resource "google_compute_network" "vpc_mgmt" {
  name                    = "${var.vpc_name}-mgmt"
  auto_create_subnetworks = false
}

resource "google_compute_network" "vpc_untrust" {
  name                    = "${var.vpc_name}-untrust"
  auto_create_subnetworks = false
}

resource "google_compute_network" "vpc_trust" {
  name                    = "${var.vpc_name}-trust"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "mgmt" {
  name          = "${var.vpc_name}-mgmt"
  ip_cidr_range = var.mgmt_subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_mgmt.id
}

resource "google_compute_subnetwork" "public" {
  name                     = "${var.vpc_name}-public"
  ip_cidr_range            = var.public_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc_untrust.id
  private_ip_google_access = false
}

resource "google_compute_subnetwork" "private" {
  name                     = "${var.vpc_name}-private"
  ip_cidr_range            = var.private_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc_trust.id
  private_ip_google_access = true
}

############################
# IAM Service Account Module #
############################

module "iam_service_account" {
  source = "PaloAltoNetworks/swfw-modules/google//modules/iam_service_account"

  service_account_id = var.service_account_id
  display_name       = var.service_account_display_name
  project_id         = var.project_id
  
  roles = var.service_account_roles
}

############################
# Bootstrap Module           #
############################

module "bootstrap" {
  count  = var.enable_bootstrap ? 1 : 0
  source = "PaloAltoNetworks/swfw-modules/google//modules/bootstrap"

  location            = var.region
  service_account     = module.iam_service_account.email
  files               = var.bootstrap_files
  bootstrap_files_dir = var.bootstrap_files_dir
}

############################
# Panorama Module            #
############################

module "panorama" {
  count  = var.enable_panorama ? 1 : 0
  source = "PaloAltoNetworks/swfw-modules/google//modules/panorama"

  name             = "panorama"
  region           = var.region
  zone             = var.zone
  machine_type     = var.panorama_machine_type
  panorama_version = var.panorama_version
  ssh_keys         = var.panorama_ssh_keys

  # Installed module requires single subnet and IP flags
  subnet            = google_compute_subnetwork.mgmt.self_link
  private_static_ip = var.panorama_mgmt_private_ip
  attach_public_ip  = var.panorama_create_public_ip

  log_disks = var.panorama_log_disks

  # Installed module uses `service_account` (email)
  service_account = module.iam_service_account.email

  scopes = concat(
    [
      "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
    ],
    var.enable_bootstrap ? ["https://www.googleapis.com/auth/devstorage.read_only"] : []
  )

  tags = ["panorama-mgmt"]
}

########################################
# GCP Firewall rules (not Palo Alto)   #
########################################

# Allow SSH/HTTPS to firewall management interface
resource "google_compute_firewall" "allow_mgmt" {
  name    = "${var.vpc_name}-allow-mgmt"
  network = google_compute_network.vpc_mgmt.name

  allow {
    protocol = "tcp"
    ports    = ["22", "443"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["fw-mgmt"]
}

# Allow LB health checks to reach firewall instances
resource "google_compute_firewall" "allow_lb_health_untrust" {
  name    = "${var.vpc_name}-allow-lb-health-untrust"
  network = google_compute_network.vpc_untrust.name
  priority = 100

  allow {
    protocol = "tcp"
    ports    = [tostring(var.fw_health_check_port)]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
    "209.85.152.0/22",
    "209.85.204.0/22"
  ]

  target_tags = ["fw-untrust"]
}

resource "google_compute_firewall" "allow_lb_health_trust" {
  name    = "${var.vpc_name}-allow-lb-health-trust"
  network = google_compute_network.vpc_trust.name
  priority = 100

  allow {
    protocol = "tcp"
    ports    = [tostring(var.fw_health_check_port)]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
    "209.85.152.0/22",
    "209.85.204.0/22"
  ]

  target_tags = ["fw-trust"]
}

# Allow data-path traffic from Internet via External LB to firewall untrust NICs
resource "google_compute_firewall" "allow_untrust_ingress" {
  name    = "${var.vpc_name}-allow-untrust-ingress"
  network = google_compute_network.vpc_untrust.name

  allow {
    protocol = "tcp"
    ports    = var.ingress_lb_ports
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["fw-untrust"]
}

resource "google_compute_firewall" "allow_panorama_mgmt" {
  count   = var.enable_panorama ? 1 : 0
  name    = "allow-panorama-mgmt"
  network = google_compute_network.vpc_mgmt.name

  allow {
    protocol = "tcp"
    ports    = ["22", "443", "3978"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["panorama-mgmt"]
}

# Allow full management access from VM-Series to Panorama inside mgmt VPC
resource "google_compute_firewall" "allow_fw_to_panorama_all" {
  count   = var.enable_panorama ? 1 : 0
  name    = "${var.vpc_name}-allow-fw-to-panorama-all"
  network = google_compute_network.vpc_mgmt.name

  direction = "INGRESS"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_tags = ["fw-mgmt"]
  target_tags = ["panorama-mgmt"]
}

# Allow all data-path from private workloads (tagged) to firewall trust NICs
resource "google_compute_firewall" "allow_private_to_fw_trust_all" {
  name    = "${var.vpc_name}-allow-private-to-fw-trust-all"
  network = google_compute_network.vpc_trust.name

  direction = "INGRESS"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_tags = ["private-egress-via-fw"]
  target_tags = ["fw-trust"]
}

# Allow IAP SSH access to private instances (no external IP)
resource "google_compute_firewall" "allow_iap_ssh_private" {
  name    = "${var.vpc_name}-allow-iap-ssh-private"
  network = google_compute_network.vpc_trust.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["private-egress-via-fw"]
}

# Allow IAP SSH access to app-http instances (after removing private-egress-via-fw tag)
resource "google_compute_firewall" "allow_iap_ssh_app" {
  name    = "${var.vpc_name}-allow-iap-ssh-app"
  network = google_compute_network.vpc_trust.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["app-http"]
}

############################################
# Palo Alto VM-Series: Official Autoscaling Module #
############################################

module "autoscale" {
  source = "PaloAltoNetworks/swfw-modules/google//modules/autoscale"

  name                    = "pa-fw-v2"
  project_id             = var.project_id
  region                 = var.region
  regional_mig           = true
  image                  = var.pa_image
  machine_type           = var.machine_type
  min_vmseries_replicas  = var.min_replicas
  max_vmseries_replicas  = var.max_replicas
  
  network_interfaces = [
    # Reorder NICs so untrust becomes nic0, mgmt nic1, trust nic2
    {
      subnetwork       = google_compute_subnetwork.public.self_link
      create_public_ip = true
    },
    {
      subnetwork       = google_compute_subnetwork.mgmt.self_link
      create_public_ip = true
    },
    {
      subnetwork       = google_compute_subnetwork.private.self_link
      create_public_ip = false
    }
  ]

  service_account_email = module.iam_service_account.email
  scopes = concat(
    [
      "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
    ],
    var.enable_bootstrap ? ["https://www.googleapis.com/auth/devstorage.read_only"] : []
  )

  tags = ["fw-mgmt", "fw-untrust", "fw-trust"]

  metadata = merge(
    {
      serial-port-enable = "1"
      ssh-keys = var.fw_ssh_keys
      op-command-modes = "mgmt-interface-swap"
      mgmt-interface-swap = "enable"
      # Bootstrap exclusively via instance metadata (user data parameters)
      panorama-server = var.panorama_server
      vm-auth-key = var.vm_auth_key
      #auth-key = var.auth_key
      authcodes = var.authcodes
      tplname = var.tplname
      dgname = var.dgname
      dns-primary = var.dns_primary
      dns-secondary = var.dns_secondary
      dhcp-send-hostname = var.dhcp_send_hostname
      dhcp-send-client-id = var.dhcp_send_client_id
      #plugin-op-commands = var.plugin_op_commands
      vm-series-auto-registration-pin-id = var.vmseries_pin_id
      vm-series-auto-registration-pin-value = var.vmseries_pin_value
      type = var.mgmt_type
    },
    var.enable_bootstrap ? { vmseries-bootstrap-gce-storagebucket = module.bootstrap[0].bucket_name } : {}
  )

  # Enhanced autoscaling configuration
  autoscaler_metrics                   = var.autoscaler_metrics
  cooldown_period                     = var.cooldown_period
  scale_in_control_time_window_sec    = var.scale_in_control_time_window_sec
  scale_in_control_replicas_fixed     = var.scale_in_control_replicas_fixed

  # Delicensing configuration
  create_pubsub_topic = var.enable_delicensing
  delicensing_cloud_function_config = null

  named_ports = [
    {
      name = "hc"
      port = var.fw_health_check_port
    }
  ]
}

###########################################
# External Network Load Balancer (Ingress) #
###########################################

resource "google_compute_region_health_check" "ingress_hc" {
  name               = "pa-ingress-hc"
  region             = var.region
  check_interval_sec = 5
  timeout_sec        = 5

  tcp_health_check {
    port = var.fw_health_check_port
  }
}

resource "google_compute_region_backend_service" "ingress_backend" {
  name                  = "pa-ingress-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.ingress_hc.id]

  backend {
  group = module.autoscale.regional_instance_group_id
  balancing_mode = "CONNECTION"
  }
}

resource "google_compute_address" "ingress_ip" {
  name   = "pa-ingress-ip"
  region = var.region
}

resource "google_compute_forwarding_rule" "ingress_fr_tcp" {
  name                  = "pa-ingress-fr-tcp"
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  ports                 = var.ingress_lb_ports
  backend_service       = google_compute_region_backend_service.ingress_backend.id
  ip_address            = google_compute_address.ingress_ip.address
}

#############################################
# Internal TCP/UDP Load Balancer (Egress ILB) #
#############################################


resource "google_compute_region_health_check" "egress_hc" {
  name               = "pa-egress-hc"
  region             = var.region
  check_interval_sec = 5
  timeout_sec        = 5

  tcp_health_check {
    port = var.fw_health_check_port
  }
}

resource "google_compute_region_backend_service" "egress_backend" {
  name                  = "pa-egress-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  network               = google_compute_network.vpc_trust.id
  health_checks         = [google_compute_region_health_check.egress_hc.id]
  session_affinity      = "CLIENT_IP"

  backend {
    group = module.autoscale.regional_instance_group_id
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "egress_ilb" {
  name                  = "pa-egress-ilb"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  ip_protocol           = "TCP"
  all_ports             = true
  backend_service       = google_compute_region_backend_service.egress_backend.id
  network               = google_compute_network.vpc_trust.id
  subnetwork            = google_compute_subnetwork.private.id
}

# Default route for private instances: next hop via ILB
resource "google_compute_route" "private_default_via_ilb" {
  name        = "private-default-via-ilb"
  network     = google_compute_network.vpc_trust.name
  dest_range  = "0.0.0.0/0"
  priority    = 900
  next_hop_ilb = google_compute_forwarding_rule.egress_ilb.self_link
  tags        = ["private-egress-via-fw"]
}

####################################
# Sample private VM for egress test #
####################################

resource "google_compute_instance" "private_vm" {
  name         = "private-test-vm"
  machine_type = "e2-medium"
  zone         = var.zone

  tags = ["app-http", "private-egress-via-fw"]

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    network_ip = "10.0.1.10"
  }

  metadata = {
    ssh-keys               = "<Put_Your_Own_Ssh_Key>"
    metadata_startup_script = <<-EOF
      #!/usr/bin/env bash
      set -euxo pipefail
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
      echo "Hello World from Ubuntu 22.04 behind Palo Alto Firewall" > /var/www/html/index.nginx-debian.html
      systemctl enable nginx
      systemctl restart nginx
    EOF
  }
}

# Allow HTTP from firewall trust NICs to app VMs in private subnet
resource "google_compute_firewall" "allow_app_http" {
  name    = "${var.vpc_name}-allow-app-http"
  network = google_compute_network.vpc_trust.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_tags = ["fw-trust"]
  target_tags = ["app-http"]
}