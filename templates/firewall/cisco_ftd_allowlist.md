Cisco FTD inbound allow-list template

Use NISE as the source of truth for scored services and ports. Update this matrix to match NISE.

Policy placement
- Use the Access Control Policy (ACP) for inbound allow rules.
- Keep NAT mappings unchanged unless injected.

Rule order
1) Allow scored services to their public IPs.
2) Allow ICMP (per rules).
3) Deny all other inbound public traffic (log connections).

Allow-list matrix (fill team number)
| Service | Protocol | Port(s) | Public IP | Internal host | Notes |
| --- | --- | --- | --- | --- | --- |
| Ecom web | tcp | 80,443 | 172.25.36.11 | 172.20.242.30 | Ubuntu Ecom |
| Windows web | tcp | 80,443 | 172.25.36.140 | 172.20.240.101 | IIS |
| SMTP | tcp | 25 (maybe 587) | 172.25.36.39 | 172.20.242.40 | Fedora Webmail |
| POP3 | tcp | 110 (maybe 995) | 172.25.36.39 | 172.20.242.40 | Fedora Webmail |
| DNS | udp/tcp | 53 | 172.25.36.155 | 172.20.240.102 | AD/DNS |
| FTP control | tcp | 21 | 172.25.36.162 | 172.20.240.104 | Server 2022 FTP |
| FTP passive | tcp | <passive_range> | 172.25.36.162 | 172.20.240.104 | Must match IIS config |
| ICMP | icmp | echo | all public IPs | n/a | Except PA core port |

Notes
- Log at end for inbound denies to reduce noise.
- Avoid aggressive IPS policies until scoring is stable.
- Do not allow Splunk or management ports inbound from untrust.

