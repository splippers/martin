# FOGDoctor CLI — implementation brief

Authoring notes for a future single-file `fogdoctor.py` tool (not executable build output). See also `docs/Software Specs/FOGDoctor.md`.

---

Create /WENDY/FOGDoctor/fogdoctor.py as a single-file CLI.

Use Click for CLI, Rich for tables, Paramiko for SSH.

Implement class FOGDoctor(host, user, key=None, password=None):
    - connect() -> bool
    - check_services() -> dict
    - check_nic_bind() -> dict
    - check_udp_traffic() -> dict
    - check_log_errors() -> dict
    - check_bitrate() -> dict
    - run_all() -> list[dict]

Each check returns: {"id": "svc", "name": "Services", "passed": bool, "detail": str, "fix": str}

Implement check_igmp() on client side using scapy.all: send IGMPv2 Membership Report to 239.192.0.1.

Main CLI 'check' command: runs all checks, prints Rich table with [green]✓[/green] or [red]✗[/red].
After table, print numbered list of fixes for failed checks.

Add --json flag to output list[dict] only.

Add GoogleSheetsLogger class: if ~/.fogdoctor/token.json exists, append results to first sheet.
Add 'init-sheet' command: run OAuth flow, create 'FOGDoctor Audits' sheet, save token.

Add __version__ = "0.1.0". Add MIT license header.

Include if __name__ == "__main__": cli()
