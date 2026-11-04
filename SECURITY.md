# Security

Report vulnerabilities privately to walid.sadfi@evolurise.com. Acknowledgement within 72 hours.

Operating notes:

- `overlays/dev` ships literal secrets for local clusters only. Never apply it to a shared cluster.
- `set_real_ip_from` trusts private ranges; narrow it to your ingress controller's pod CIDR.
- The NetworkPolicy for WordPress allows egress to the internet on 80/443 (payment gateways, updates). Tighten with FQDN policies if your CNI supports them.
- Backups are encrypted with a symmetric passphrase; store it outside the cluster and outside the bucket.
