#!/usr/bin/env python3
"""
M.A.R.T.I.N. Maternity Ward — Web Console
Flask-based web UI for managing golden images, driver cache, and network.
"""

import os
import json
import subprocess
import time
import threading
from datetime import datetime
from pathlib import Path

import psutil
from flask import Flask, render_template, jsonify, request, Response, stream_with_context

app = Flask(__name__)

BASE = Path("/opt/martin/maternity")
DRIVERS = BASE / "drivers"
CAPTURES = Path("/var/lib/maternity/captures")
FRESHNESS_DB = Path("/var/lib/maternity/freshness.db")
DRIVER_ROOT = Path("/var/lib/maternity/drivers")
PIPELINE = BASE / "maternity-pipeline.sh"
FRESHNESS_TRACKER = BASE / "freshness-tracker"
DRIVER_CACHE = DRIVERS / "driver-cache.sh"

# ── Helpers ─────────────────────────────────────────────────────────

def run(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return {"ok": r.returncode == 0, "out": r.stdout, "err": r.stderr, "code": r.returncode}
    except subprocess.TimeoutExpired as e:
        return {"ok": False, "out": "", "err": f"Timed out after {timeout}s"}
    except FileNotFoundError:
        return {"ok": False, "out": "", "err": "Command not found"}

def sudo(cmd, timeout=30):
    return run(["sudo"] + cmd, timeout)

def get_vm_info():
    r = sudo(["virsh", "list", "--all", "--name"])
    if not r["ok"]:
        return []
    names = [n.strip() for n in r["out"].splitlines() if n.strip()]
    vms = []
    for name in names:
        info = sudo(["virsh", "dominfo", name])
        state = "unknown"
        vnc = ""
        if info["ok"]:
            for line in info["out"].splitlines():
                if "State:" in line:
                    state = line.split(":")[1].strip()
                if "Autostart:" in line:
                    pass
        display = sudo(["virsh", "domdisplay", name])
        if display["ok"]:
            vnc = display["out"].strip()
        autostart = sudo(["virsh", "autostart", name])
        auto = "yes" if autostart["ok"] and "enabled" in autostart["out"] else "no"
        vms.append({"name": name, "state": state, "vnc": vnc, "autostart": auto})
    return vms

def get_disk_usage(path):
    r = sudo(["du", "-sh", str(path)])
    if r["ok"]:
        return r["out"].split()[0]
    return "0B"

def get_bridge_info():
    r = sudo(["ip", "-br", "addr", "show"])
    bridges = {}
    if r["ok"]:
        for line in r["out"].splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[0] in ("br-ictroom", "br-fog", "virbr0"):
                bridges[parts[0]] = {
                    "state": parts[1],
                    "ip": parts[2] if len(parts) > 2 else "",
                }
    for br in bridges:
        members = sudo(["bridge", "link", "show", br])
        if members["ok"]:
            bridges[br]["members"] = len([l for l in members["out"].splitlines() if l.strip()])
    return bridges

def get_dhcp_status():
    r = sudo(["systemctl", "is-active", "isc-dhcp-server"])
    active = r["out"].strip() if r["ok"] else "inactive"
    leases = Path("/var/lib/dhcp/dhcpd.leases")
    leases_text = ""
    if leases.exists():
        try:
            with open(leases) as f:
                leases_text = f.read()
        except:
            pass
    return {"active": active, "leases": leases_text}

# ── Routes ────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/status")
def api_status():
    uptime = datetime.now().timestamp() - psutil.boot_time()
    cpu = psutil.cpu_percent(interval=0.5)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    bridges = get_bridge_info()
    dhcp = get_dhcp_status()

    return jsonify({
        "hostname": os.uname().nodename,
        "uptime_days": round(uptime / 86400, 1),
        "cpu_percent": cpu,
        "memory": {"total_gb": round(mem.total / 1e9, 1), "used_gb": round(mem.used / 1e9, 1), "percent": mem.percent},
        "disk": {"total_gb": round(disk.total / 1e9, 1), "used_gb": round(disk.used / 1e9, 1), "percent": disk.percent},
        "bridges": bridges,
        "dhcp": dhcp,
    })

@app.route("/api/vms")
def api_vms():
    return jsonify(get_vm_info())

@app.route("/api/vm/<name>/<action>", methods=["POST"])
def api_vm_action(name, action):
    allowed = {"start", "shutdown", "destroy", "autostart", "autostart-disable"}
    if action not in allowed:
        return jsonify({"ok": False, "err": f"Unknown action: {action}"}), 400
    if action == "autostart":
        r = sudo(["virsh", "autostart", name])
    elif action == "autostart-disable":
        r = sudo(["virsh", "autostart", "--disable", name])
    else:
        r = sudo(["virsh", action, name])
    return jsonify({"ok": r["ok"], "out": r["out"], "err": r["err"]})

@app.route("/api/vm/create", methods=["POST"])
def api_vm_create():
    data = request.get_json()
    name = data.get("name", "Win10-Golden")
    ram = data.get("ram", 4096)
    cpus = data.get("cpus", 2)
    disk_gb = data.get("disk_gb", 64)
    iso = data.get("iso", "")
    drivers_iso = data.get("drivers_iso", "")

    env = {**os.environ, "VM_NAME": name, "RAM": str(ram), "CPUS": str(cpus), "DISK_GB": str(disk_gb)}
    if not iso or not os.path.exists(iso):
        return jsonify({"ok": False, "err": f"ISO not found: {iso}"}), 400
    cmd = ["sudo", str(PIPELINE), "create", iso]
    if drivers_iso:
        cmd.append(drivers_iso)

    def stream():
        yield json.dumps({"step": "Creating VM...", "status": "running"}) + "\n"
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
        for line in proc.stdout:
            yield json.dumps({"step": line.strip(), "status": "running"}) + "\n"
        proc.wait()
        yield json.dumps({"step": "Done", "status": "ok" if proc.returncode == 0 else "error"}) + "\n"

    return Response(stream_with_context(stream()), mimetype="application/x-ndjson")

@app.route("/api/freshness")
def api_freshness():
    r = sudo([str(FRESHNESS_TRACKER), "list"], timeout=10)
    reports = r["out"] if r["ok"] else "No reports"
    return jsonify({"reports": reports, "ok": r["ok"]})

@app.route("/api/freshness/<image_name>")
def api_freshness_detail(image_name):
    r = sudo([str(FRESHNESS_TRACKER), "show", image_name], timeout=10)
    return jsonify({"detail": r["out"], "ok": r["ok"]})

@app.route("/api/freshness/report/<image_name>")
def api_freshness_report(image_name):
    r = sudo([str(FRESHNESS_TRACKER), "report", image_name], timeout=10)
    return jsonify({"report": r["out"], "ok": r["ok"]})

@app.route("/api/drivers")
def api_drivers():
    r = sudo([str(DRIVER_CACHE), "status"], timeout=10)
    return jsonify({"status": r["out"], "ok": r["ok"], "err": r["err"]})

@app.route("/api/drivers/list")
def api_drivers_list():
    r = sudo([str(DRIVER_CACHE), "list"], timeout=10)
    return jsonify({"list": r["out"], "ok": r["ok"]})

@app.route("/api/drivers/update", methods=["POST"])
def api_drivers_update():
    def stream():
        yield json.dumps({"step": "Updating driver cache...", "status": "running"}) + "\n"
        proc = subprocess.Popen(["sudo", str(DRIVER_CACHE), "update"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in proc.stdout:
            yield json.dumps({"step": line.strip(), "status": "running"}) + "\n"
        proc.wait()
        yield json.dumps({"step": "Driver cache update complete", "status": "ok" if proc.returncode == 0 else "error"}) + "\n"
    return Response(stream_with_context(stream()), mimetype="application/x-ndjson")

@app.route("/api/network")
def api_network():
    bridges = get_bridge_info()
    dhcp = get_dhcp_status()
    interfaces = sudo(["ip", "-br", "link"])
    ifaces = []
    if interfaces["ok"]:
        for line in interfaces["out"].splitlines():
            parts = line.split()
            if len(parts) >= 2:
                ifaces.append({"name": parts[0], "state": parts[1]})
    return jsonify({"bridges": bridges, "dhcp": dhcp, "interfaces": ifaces})

@app.route("/api/dhcp/restart", methods=["POST"])
def api_dhcp_restart():
    r = sudo(["systemctl", "restart", "isc-dhcp-server"])
    return jsonify({"ok": r["ok"], "out": r["out"], "err": r["err"]})

@app.route("/api/dhcp/config")
def api_dhcp_config():
    path = "/etc/dhcp/dhcpd.conf"
    try:
        with open(path) as f:
            return jsonify({"ok": True, "config": f.read()})
    except Exception as e:
        return jsonify({"ok": False, "err": str(e)})

@app.route("/api/vnc/<name>")
def api_vnc_proxy(name):
    vms = get_vm_info()
    for vm in vms:
        if vm["name"] == name:
            return jsonify({"vnc": vm["vnc"], "state": vm["state"]})
    return jsonify({"vnc": "", "state": "not found"})

@app.route("/api/captures")
def api_captures():
    captures = []
    if CAPTURES.exists():
        for f in sorted(CAPTURES.glob("*.qcow2"), reverse=True):
            meta = {}
            meta_path = f.with_suffix(f.suffix + ".meta")
            if meta_path.exists():
                try:
                    meta = json.loads(meta_path.read_text())
                except:
                    pass
            captures.append({
                "name": f.stem,
                "size": get_disk_usage(f),
                "path": str(f),
                "modified": datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
                "meta": meta,
            })
    return jsonify(captures)

@app.route("/api/logs")
def api_logs():
    lines = request.args.get("lines", 50, type=int)
    sources = [
        "/var/log/maternity/driver-cache.log",
        "/var/log/syslog",
    ]
    logs = {}
    for src in sources:
        p = Path(src)
        if p.exists():
            try:
                logs[src] = subprocess.run(["sudo", "tail", "-n", str(lines), src], capture_output=True, text=True, timeout=5).stdout
            except:
                logs[src] = "(unreadable)"
    return jsonify(logs)

@app.route("/api/actions/run", methods=["POST"])
def api_run_action():
    data = request.get_json()
    command = data.get("command", "")
    args = data.get("args", [])
    if command == "inject-freshness":
        r = sudo([str(PIPELINE), "inject-freshness", args[0] if args else "golden-image"])
    elif command == "sysprep":
        r = sudo([str(PIPELINE), "sysprep"])
    elif command == "capture":
        r = sudo([str(PIPELINE), "capture", args[0] if args else "golden-image"])
    elif command == "upload":
        r = sudo([str(PIPELINE), "upload", args[0] if args else "golden-image"])
    else:
        return jsonify({"ok": False, "err": f"Unknown command: {command}"}), 400
    return jsonify({"ok": r["ok"], "out": r["out"], "err": r["err"]})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
