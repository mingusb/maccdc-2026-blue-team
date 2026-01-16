Scored services (baseline expectations)

NISE is the source of truth for what is scored. Do not guess ports or endpoints.

Typical service checks
- HTTP: content may be compared byte-for-byte.
- HTTPS: same as HTTP, with TLS.
- SMTP: mail send/receive via valid account.
- POP3: logins often use AD usernames.
- DNS: A queries against the DNS server.
- FTP: control + passive range must match firewall and server config.

Gotchas
- Changing web content can break scoring even if the service is up.
- Blocking TCP/53 can break DNS scoring.
- FTP passive range must be open end-to-end.

