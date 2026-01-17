Splunk forwarder setup (Linux + Windows)

Goal
- Send minimal, high-value logs to the Splunk server without breaking scoring.

Assumptions
- Splunk server IP: 172.20.242.20
- Splunk receiving port: 9997 (enable on Splunk first)
- Use the Universal Forwarder (UF) installer staged ahead of time.

Enable receiving on Splunk server (run on Splunk host)
```
/opt/splunk/bin/splunk enable listen 9997 -auth admin:<splunk_admin_pass>
```

Linux (Ubuntu/Fedora/Oracle)
1) Use the helper to install/configure (rpm/deb/tgz supported):
```
sudo bash scripts/splunk/forwarder_linux.sh --mode dry-run --installer <path_to_uf_pkg> --splunk-pass <forwarder_pass>
sudo bash scripts/splunk/forwarder_linux.sh --mode apply --installer <path_to_uf_pkg> --splunk-pass <forwarder_pass>
sudo bash scripts/splunk/forwarder_linux.sh --mode list
```
2) Default inputs include auth logs (`/var/log/auth.log` and `/var/log/secure`).

Windows
1) Use the helper to install/configure (MSI):
```
.\scripts\splunk\forwarder_windows.ps1 -Mode dry-run -InstallerPath <path_to_uf_msi> -SplunkPass <forwarder_pass>
.\scripts\splunk\forwarder_windows.ps1 -Mode apply -InstallerPath <path_to_uf_msi> -SplunkPass <forwarder_pass>
.\scripts\splunk\forwarder_windows.ps1 -Mode list
```
2) Default inputs include Security and System Event Logs.

Minimal inputs.conf examples
Linux (place in `etc/system/local/inputs.conf`):
```
[monitor:///var/log/auth.log]
index=maccdc
sourcetype=linux_secure

[monitor:///var/log/secure]
index=maccdc
sourcetype=linux_secure
```

Windows (place in `etc/system/local/inputs.conf`):
```
[WinEventLog://Security]
index=maccdc
renderXml=false

[WinEventLog://System]
index=maccdc
renderXml=false
```

Per-box quick commands (copy/paste)

Ubuntu Ecom (24.04)
```
sudo bash scripts/splunk/forwarder_linux.sh --mode apply --installer <splunkforwarder.deb_or_tgz> --splunk-pass <forwarder_pass>
```

Fedora Webmail (42)
```
sudo bash scripts/splunk/forwarder_linux.sh --mode apply --installer <splunkforwarder.rpm_or_tgz> --splunk-pass <forwarder_pass>
```

Oracle Linux Splunk host (optional local forwarder)
```
sudo bash scripts/splunk/forwarder_linux.sh --mode apply --installer <splunkforwarder.rpm_or_tgz> --splunk-pass <forwarder_pass>
```

Ubuntu Workstation (jump host)
```
sudo bash scripts/splunk/forwarder_linux.sh --mode apply --installer <splunkforwarder.deb_or_tgz> --splunk-pass <forwarder_pass>
```

Windows 11 Workstation
```
.\scripts\splunk\forwarder_windows.ps1 -Mode apply -InstallerPath <splunkforwarder.msi> -SplunkPass <forwarder_pass>
```

Windows Server 2019 AD/DNS
```
.\scripts\splunk\forwarder_windows.ps1 -Mode apply -InstallerPath <splunkforwarder.msi> -SplunkPass <forwarder_pass>
```

Windows Server 2019 Web (IIS)
```
.\scripts\splunk\forwarder_windows.ps1 -Mode apply -InstallerPath <splunkforwarder.msi> -SplunkPass <forwarder_pass>
```

Windows Server 2022 FTP
```
.\scripts\splunk\forwarder_windows.ps1 -Mode apply -InstallerPath <splunkforwarder.msi> -SplunkPass <forwarder_pass>
```

Optional extra inputs (copy/paste into `inputs.conf`)

Linux web logs (Apache/Nginx)
```
[monitor:///var/log/apache2/access.log]
index=maccdc
sourcetype=access_combined

[monitor:///var/log/apache2/error.log]
index=maccdc
sourcetype=apache_error

[monitor:///var/log/nginx/access.log]
index=maccdc
sourcetype=nginx_access

[monitor:///var/log/nginx/error.log]
index=maccdc
sourcetype=nginx_error
```

Linux mail logs
```
[monitor:///var/log/maillog]
index=maccdc
sourcetype=maillog
```

Windows IIS logs
```
[monitor://C:\\inetpub\\logs\\LogFiles]
index=maccdc
recursive=true
```

Windows FTP logs
```
[monitor://C:\\inetpub\\logs\\LogFiles]
index=maccdc
recursive=true
```

Windows AD/DNS extra logs
```
[WinEventLog://Directory Service]
index=maccdc
renderXml=false

[WinEventLog://DNS Server]
index=maccdc
renderXml=false
```

Validation
- From Splunk, search `index=maccdc` and confirm new events arrive.
- Test with a known logon attempt and check the event appears.

Notes
- Keep inputs minimal to avoid storage and noise.
- Do not enable anything that could break scored services.
