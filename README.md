# GCP PANW Perimeter Firewall with MIG AutoScaling

## 1) Project Scope and Outcome

- Deploys a production-ready perimeter architecture on GCP using Palo Alto VM‑Series in a Regional Managed Instance Group (MIG) with autoscaling.
- Provides three VPCs: `mgmt`, `untrust` (public), and `trust` (private), each with its own subnetwork.
- Ingress: An External TCP Network Load Balancer forwards public traffic to firewall instances on the untrust NIC.
- Egress: An Internal TCP/UDP Load Balancer (ILB) forwards private workload traffic to firewall instances on the trust NIC; a default route pins workload egress through the ILB.
- Health checks allowed on both sides (trust/untrust) to ensure LB stability; GCP VPC rules enable data path and management access.
- Optional Panorama deployment integrates centralized management, templates, and device groups. Bootstrap supports metadata and/or bucket-based workflows for first‑boot configuration.
- Outcome: A functional perimeter with documented inbound/outbound flows, ready to verify using `private-test-vm` (Nginx) and external/egress LB health.

## 2) Prerequisites and Variables Overview

### Platform Prerequisites
- Enable required APIs in the target project: `compute.googleapis.com`, `logging.googleapis.com`, `monitoring.googleapis.com`, and if using bootstrap buckets, `storage.googleapis.com`.
- Ensure IAM permissions to create networks, instance templates/MIGs, forwarding rules, firewall rules, health checks, and service accounts.
- Confirm region/zone capacity for the selected machine types.

### Core Variables (from `variables.tf`)
- `project_id` (string): Deployment project.
- `region` (string), `zone` (string): Location for resources.
- `vpc_name` (string): Base name for VPCs and resources.
- Subnet CIDRs:
  - `public_subnet_cidr` (string): Untrust subnet.
  - `private_subnet_cidr` (string): Trust subnet.
  - `mgmt_subnet_cidr` (string): Management subnet.
- Image and sizing:
  - `pa_image` (string): VM‑Series image self_link/family.
  - `machine_type` (string): Firewall instance type.
- Access and LBs:
  - `ssh_source_ranges` (list(string)): CIDRs allowed for mgmt SSH/HTTPS.
  - `fw_health_check_port` (number): LB health‑check TCP port (default `80`).
  - `ingress_lb_ports` (list(string)): External NLB service ports (default `["80","443"]`).
- Autoscale:
  - `min_replicas` (number), `max_replicas` (number).
  - `autoscaler_metrics` (map): Metric and target (e.g., CPU utilization 0.6).
  - `cooldown_period`, `scale_in_control_time_window_sec`, `scale_in_control_replicas_fixed`.
- Bootstrap (optional):
  - `enable_bootstrap` (bool): Enable bucket‑based bootstrap module.
  - `bootstrap_files_dir` (string): Local dir of bootstrap artifacts.
  - `bootstrap_files` (map(string)): Local→bucket paths for config files.
- Panorama:
  - `enable_panorama` (bool), `panorama_ssh_keys` (string), `panorama_machine_type` (string), `panorama_version` (string), `panorama_log_disks` (list(object)).
  - `panorama_mgmt_private_ip` (string): Static mgmt IP; `panorama_create_public_ip` (bool).
- VM‑Series SSH keys:
  - `fw_ssh_keys` (string): Admin SSH public keys for VM‑Series.

### IAM Service Account
- `service_account_id` (string), `service_account_display_name` (string), `service_account_description` (string).
- `service_account_roles` (list(string)): Recommended includes:
  - `roles/compute.instanceAdmin.v1`, `roles/compute.networkViewer`,
  - `roles/storage.objectViewer`, `roles/logging.logWriter`,
  - `roles/monitoring.metricWriter`, `roles/monitoring.viewer`.

### MIG Instance Template Metadata (used by autoscale module)
Pre-requiste : To configure Bootstrap parameters Panorama should be deployed and configured.
- Bootstrap and registration keys:
  - `panorama-server`: Panorama address for registration.
  - `vm-auth-key`: Panorama VM auth key.
  - `authcodes`: BYOL licensing auth codes (comma-separated).
  - `tplname`: Panorama Template name.
  - `dgname`: Panorama Device Group name.
  - `vm-series-auto-registration-pin-id`, `vm-series-auto-registration-pin-value`: Auto-registration pins.
- Management and DNS:
  - `type`: `dhcp-client` or `static` mgmt addressing.
  - `dns-primary`, `dns-secondary`: DNS servers.
  - `dhcp-send-hostname`, `dhcp-send-client-id`: DHCP behaviors on mgmt.
- Access and debug:
  - `serial-port-enable`: Enable serial console.
  - `ssh-keys`: VM‑Series admin SSH public keys.
- Optional:
  - `plugin-op-commands`: e.g., `panorama-licensing-mode-on`.
  - `vmseries-bootstrap-gce-storagebucket`: Injected when `enable_bootstrap = true` to reference the bootstrap GCS bucket.

## 3) Bootstrap Process and Workflow

- Two supported approaches:
  - Bucket‑based bootstrap (module enabled):
    - Terraform uploads specified files from `bootstrap_files` into a GCS bucket (via the bootstrap module).
    - Autoscale MIG instances receive `vmseries-bootstrap-gce-storagebucket` metadata pointing to the bucket.
    - On first boot, VM‑Series pulls `init-cfg.txt`, `bootstrap.xml`, and any additional content from the bucket.
  - Metadata‑only bootstrap:
    - Core bootstrap parameters are provided via instance metadata (e.g., `panorama-server`, `vm-auth-key`, `tplname`, `dgname`, `authcodes`).
    - Useful for lightweight setups or when GCS access is restricted.
- Bucket-based approach Typical file set in `./bootstrap/config/`:
  - `init-cfg.txt`: Device bootstrap including mgmt config, Panorama, and registration settings.
  - `bootstrap.xml`: Base configuration (interfaces, zones, policies) tailored to the three‑VPC topology.

## 4) Panorama GCP Plugin Configuration

- Purpose: Centralize management, policy, templates, and licensing for the VM‑Series autoscale group.
- Key steps:
  - Import VM‑Series devices into Panorama automatically using `vm-auth-key`, `tplname`, and `dgname` values set in instance metadata.
  - Ensure Panorama has network reachability to the mgmt subnet; in Terraform, you can set `panorama_mgmt_private_ip` and optionally `panorama_create_public_ip` for management access.
  - Apply appropriate Templates and Device Groups (`GCP_MIG_Stack`, `GCP_MIG_DG`) matching the metadata.
  - If using licensing via plugin or auth codes, verify `authcodes` and related plugin settings align with your licensing mode.
  - For logs and scale insights, attach additional disks as needed via `panorama_log_disks` and confirm `roles/logging.logWriter` and `roles/monitoring.metricWriter` permissions on the service account.
- Best practices:
  - Keep Template variables aligned with Terraform outputs (interfaces mapped: untrust `nic0`, mgmt `nic1`, trust `nic2`).
  - Use consistent naming and labels for autoscale to simplify device onboarding.
  - Validate connectivity with Panorama before enabling strict policies in the perimeter.

## 5) Traffic Flows (Ingress and Egress)

### Ingress (Internet → Private Workload via Firewall)
- External NLB receives client traffic on `ingress_lb_ports` and forwards to a healthy firewall instance on the untrust NIC (`nic0`).
- Firewall applies security policies and DNAT for app services (e.g., HTTP to `10.0.1.10`).
- Traffic flows `External LB → Firewall (untrust) → Firewall (trust) → Private VM`.
- Return path options:
  - Without inbound SNAT: Private VM replies to the original client IP; default route via ILB sends `VM → ILB → Firewall (trust) → Firewall (untrust) → Internet`.
  - With inbound SNAT (recommended for symmetry): Firewall SNATs to its trust IP when sending inbound flows to the VM; VM replies directly to Firewall trust.
- Health checks: VPC firewall rules explicitly allow GCP health check ranges (`35.191.0.0/16`, `130.211.0.0/22`, `209.85.152.0/22`, `209.85.204.0/22`) on the configured port to `fw-untrust`.

### Egress (Private Workload → Internet via Firewall)
- `private-test-vm` has tag `private-egress-via-fw` and default route `0.0.0.0/0` pointing to the ILB (`next_hop_ilb`).
- ILB forwards to a healthy firewall instance via the trust NIC.
- Firewall applies outbound security and SNAT to a public address (firewall external IP or Cloud NAT).
- Return traffic from the internet returns to the firewall and is forwarded back to the private VM (often via ILB as the next hop).
- Health checks: Trust‑side VPC rule allows the same GCP health check ranges on the configured port to `fw-trust`.

### Key Notes
- External LB targets `nic0` of backends; ensure untrust NIC is first in the autoscale `network_interfaces` array.
- ILB delivers to the NIC attached to the trust network; session affinity is `CLIENT_IP` for better symmetry.
- If ILB or NLB health shows drops by `default-deny-ingress`, confirm the trust/untrust health‑check allow rules include all required GCP ranges and correct `target_tags`.
- For strict symmetry on ingress, enable inbound SNAT in firewall policy.

## Validation
- Verify LB health:
  - External: `gcloud compute backend-services get-health pa-ingress-backend --region <region>`
  - Internal: `gcloud compute backend-services get-health pa-egress-backend --region <region>`
- Confirm VPC rules:
  - `gcloud compute firewall-rules describe <vpc_name>-allow-lb-health-untrust`
  - `gcloud compute firewall-rules describe <vpc_name>-allow-lb-health-trust`
- Test:
  - Ingress: `curl http://<ingress_lb_ip>` returns Nginx page from `private-test-vm`.
  - Egress: `curl ifconfig.me` from `private-test-vm` returns firewall’s public NAT IP (or Cloud NAT IPs).

---
For deeper diagrams and step‑by‑step flows, see `Traffic_Flows.md`.
