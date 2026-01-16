System inventory (from VM table)

Notes
- Initial credentials are stored in `secrets/credentials.md` (gitignored). Rotate and update after first login.
- Public IPs are in the `172.25.36.*` space. Do not move services between them.

| VM | Name | Version | IP | Public IP or Mgmt IP |
| --- | --- | --- | --- | --- |
| 1 | Ubuntu Ecom | Server 24.04.3 | 172.20.242.30 | 172.25.36.11 |
| 2 | Fedora Webmail | Fedora 42 | 172.20.242.40 | 172.25.36.39 |
| 3 | Splunk | Oracle Linux 9.2 / Splunk 10.0.2 | 172.20.242.20 | 172.25.36.9 |
| 4 | Ubuntu Wks | Desktop 24.04.3 | dhcp | dynamic |
| 5 | Server 2019 AD/DNS | Server 2019 Std | 172.20.240.102 | 172.25.36.155 |
| 6 | Server 2019 Web | Server 2019 Std | 172.20.240.101 | 172.25.36.140 |
| 7 | Server 2022 FTP | Server 2022 Std | 172.20.240.104 | 172.25.36.162 |
| 8 | Windows 11 Wks | Windows 11 24H2 | 172.20.240.100 | 172.25.36.144 |
| 9 | Palo Alto | 11.0.2 | outside: 172.16.101.254/24; inside: 172.20.242.254/24 | Mgmt: 172.20.242.150 |
| 10 | Cisco FTD | 7.2.9 | outside: 172.16.102.254/24; inside: 172.20.240.254/24; external: 172.31.21.2/29 | Mgmt: 172.20.240.200 |
| 11 | VyOS Router | 1.4.3 | net1: 172.16.101.1/24; net2: 172.16.102.1/24 | n/a |
