Tools

service_check.py
- Safe service validation using explicit targets only (no scanning).
- Uses standard Python libraries only.
- Supports per-service `enabled` flags and HTTP `expect_statuses` lists.

Usage
1) Edit `config/services.json` for your targets (or copy `tools/service_check.example.json` over it).
2) Run `python3 tools/service_check.py` from a jump host.

Tips
- Set `"enabled": false` to skip a service without deleting it.
- Use `expect_statuses` like `[200, 301, 302]` for redirect-heavy sites.

Output
- Results are written to `artifacts/service_checks/<timestamp>.json`.
- Exit code is 0 if all checks pass, 2 if any check fails.
