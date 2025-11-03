# Traffic Flows: Inbound and Outbound

This document explains how traffic reaches `private-test-vm` (running Nginx on TCP/80) from the internet via the external load balancer, and how outbound flows from `private-test-vm` reach the internet and return.

## Topology Overview
- Networks
  - `vpc_untrust` (public): Firewall untrust interface; external LB targets this NIC.
  - `vpc_trust` (private): Firewall trust interface and `private-test-vm` (`10.0.1.10`).
  - `vpc_mgmt` (management): Firewall management.
- Load balancers
  - External LB (TCP/80): Frontends internet users to the firewall untrust NIC (regional external TCP/UDP LB).
  - Internal LB (ILB): Used as next hop for default route tagged `private-egress-via-fw`; targets firewall trust NIC in `vpc_trust`.
- Instances
  - Firewall MIG: Untrust NIC (`nic0`) on `vpc_untrust` with public egress IP; Trust NIC on `vpc_trust`.
  - `private-test-vm` (`10.0.1.10`): Tags `app-http`, `private-egress-via-fw`; Nginx enabled and listening on TCP/80.
- Firewall policies
  - DNAT: External LB inbound TCP/80 → `10.0.1.10`.
  - Security policy: Allow inbound HTTP from untrust → trust.
  - SNAT: Outbound to internet via firewall untrust public IP (or Cloud NAT if configured).

## Inbound HTTP Flow (Internet → private-test-vm)
1. User connects to `http://<external_lb_ip>:80` from the internet.
2. External LB selects a firewall instance and forwards traffic to the firewall’s untrust NIC (`vpc_untrust`, `nic0`).
3. Firewall applies DNAT for TCP/80, translating destination to `10.0.1.10` and allowing the session via security policy.
4. Firewall forwards the packet out the trust NIC into `vpc_trust` toward `10.0.1.10`.
5. Nginx on `private-test-vm` receives the request and generates a response.

### Return Path Options (private-test-vm → Internet)
- Without inbound SNAT (current baseline)
  - `private-test-vm` responds to the original client IP.
  - The `private-egress-via-fw` tag pins its default route to the ILB in `vpc_trust`.
  - Response goes `VM → ILB → Firewall trust NIC`.
  - Firewall matches the session, reverse-DNATs, and forwards out untrust to the internet.
  - External LB continues the flow back to the user.

- With inbound SNAT (recommended for strict symmetry)
  - Firewall SNATs inbound flows to its trust IP when sending to the VM.
  - VM responds to the firewall trust IP; response returns `VM → Firewall trust`.
  - Firewall reverse-translates and sends out untrust to the internet.
  - This guarantees the return path always crosses the same firewall.

## Outbound Egress Flow (private-test-vm → Internet)
Example: `apt update` or `curl ifconfig.me`
1. `private-test-vm` sends traffic toward the internet; default route (tag `private-egress-via-fw`) points to ILB in `vpc_trust`.
2. ILB forwards to a firewall instance (trust NIC) in `vpc_trust`.
3. Firewall applies security and SNAT policies:
   - SNAT to a public IP (firewall untrust public IP) or Cloud NAT public IPs.
4. Firewall sends traffic out untrust to the internet; return traffic comes back to the firewall’s public address.
5. Firewall reverse-translates (de-SNAT) and forwards back via trust to `private-test-vm` (often via the ILB next hop).

## Health Checks and Access Considerations
- External LB health checks must be allowed to the firewall untrust interface (e.g., `35.191.0.0/16`, `130.211.0.0/22`).
- ILB health checks must be allowed to the firewall trust interface.
- IAP SSH
  - Rule in `main.tf` allows `tcp:22` from `35.235.240.0/20` to targets with `app-http`.
  - This enables IAP SSH to `private-test-vm` without external IP.

## Verification Steps
- Inbound HTTP
  - From internet: `curl http://<external_lb_ip>` should return Nginx default page.
  - On firewall: Confirm DNAT and session entries for TCP/80 untrust→trust.
  - On `private-test-vm`: `systemctl status nginx`, `ss -tnlp | findstr :80`, `sudo tail -f /var/log/nginx/access.log`.
- Outbound Egress
  - On `private-test-vm`: `curl ifconfig.me` should report the firewall’s public NAT IP (or Cloud NAT IP), and `sudo apt update` should succeed.

## Common Gotchas
- External LB targets `nic0` on backends; ensure firewall untrust is `nic0`.
- ILB delivers to the NIC attached to its backend network (`vpc_trust`), not necessarily `nic0`.
- If the firewall untrust lacks a public IP and Cloud NAT is not configured, outbound internet will fail.
- For asymmetric routing during ingress tests, enable inbound SNAT to the firewall trust IP to ensure symmetric return.

## Summary
- Inbound: Internet → External LB → Firewall untrust → DNAT to `10.0.1.10` → VM → return via ILB to firewall trust → untrust → Internet.
- Outbound: VM → ILB (`vpc_trust`) → Firewall trust → SNAT to public IP → Internet → return to firewall → trust → VM.