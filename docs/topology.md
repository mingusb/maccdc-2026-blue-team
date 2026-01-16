Topology overview

Diagrams
- `2026CCDC.png` shows the high-level layout.
- `2026CCDCOS.png` shows the VM list, versions, and IPs.

High-level layout
- VyOS router connects the Palo Alto and Cisco FTD edges.
- Palo Alto side (172.20.242.0/24): Ubuntu Ecom, Fedora Webmail, Splunk, Ubuntu workstation.
- Cisco FTD side (172.20.240.0/24): Windows Server 2019 AD/DNS, Windows Server 2019 Web, Windows Server 2022 FTP, Windows 11 workstation.

Management access
- Palo Alto management IP: 172.20.242.150 (access from Ubuntu workstation).
- Cisco FTD management IP: 172.20.240.200 (primary; access from Windows 11 workstation).
- Team packet also references `https://172.20.102.254/#/login`; treat as alternate and verify in NISE.

Router networks (per VM table)
- VyOS net1: 172.16.101.1/24
- VyOS net2: 172.16.102.1/24

Notes
- Public IPs are assigned per team number. Do not change mappings unless an inject says so.
- Maintain ICMP on all competition devices except the Palo Alto core port.
