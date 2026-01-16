VyOS router runbook

Purpose
- Keep routing/NAT stable and restrict admin access.

Before changes
- Save a config backup and record the timestamp.
- Verify current routing and NAT behavior.

Safe steps
- Restrict SSH management to jump host IPs.
- Disable unused services (but keep SSH if needed).
- Keep existing routes and NAT mappings unless injected.

Verification
- Confirm routing between subnets still works.
- Re-check NISE after any change.

Rollback
- Restore the saved config if routing breaks.

