Splunk forwarder setup (Linux + Windows)

Goal
- Send minimal, high-value logs to the Splunk server without breaking scoring.

Assumptions
- Splunk server IP: 172.20.242.20
- Splunk receiving port: 9997 (enable on Splunk first)
- Use the Universal Forwarder (UF) installer staged ahead of time.

Linux (Ubuntu/Fedora/Oracle)
1) Install the forwarder package (rpm or tgz).
2) Start and accept license:
   - `/opt/splunkforwarder/bin/splunk start --accept-license --answer-yes`
3) Enable boot start:
   - `/opt/splunkforwarder/bin/splunk enable boot-start`
4) Set a forward-server:
   - `/opt/splunkforwarder/bin/splunk add forward-server 172.20.242.20:9997 -auth admin:<forwarder_pass>`
5) Add key logs (pick what exists):
   - Ubuntu: `/var/log/auth.log`
   - Fedora/Oracle: `/var/log/secure`
   - Also consider `/var/log/syslog` or `/var/log/messages`

Windows
1) Install the UF MSI (use a pre-staged installer).
2) During install, set the receiving indexer: 172.20.242.20:9997.
3) Enable key Event Logs:
   - Security (logons, account changes)
   - System (service changes, reboots)
   - PowerShell (if enabled)

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

Validation
- From Splunk, search `index=maccdc` and confirm new events arrive.
- Test with a known logon attempt and check the event appears.

Notes
- Keep inputs minimal to avoid storage and noise.
- Do not enable anything that could break scored services.

