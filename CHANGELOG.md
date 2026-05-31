# Changelog

## 0.1.0

- Initial public release
- Wake-on-LAN relay over Tailscale SSH
- Android/Termux relay setup (auto-deploy Python WoL script)
- Sunshine readiness checks (TCP port 47990)
- Config file: `tailwake.env` with `--config` flag and auto-discovery
- Commands: doctor, status, wake, wait, sunshine, wake-and-wait, setup, test-ssh
- SSH ControlMaster with per-target control paths
- Remote TCP checks via inline Python (no nc/curl/telnet needed)
- Hacker-styled terminal UI with ASCII banner
- Documentation in English
- MIT license
