#!/usr/bin/python
"""Apply Zephyr's power-source policy and internal-display refresh rate."""
import json
import subprocess
from pathlib import Path
from gi.repository import Gio, GLib

last_battery = None
last_policy = None
bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def property_value(service, path, interface, name):
    return bus.call_sync(service, path, "org.freedesktop.DBus.Properties", "Get",
                         GLib.Variant("(ss)", (interface, name)), GLib.VariantType("(v)"),
                         Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]


def load_policy():
    try:
        data = json.loads((Path.home() / ".local/state/zephyr/policy.json").read_text())
        if not isinstance(data, dict):
            return {}
        return data
    except (OSError, ValueError):
        return {}


def update(*_args):
    global last_battery, last_policy
    try:
        battery = property_value("org.freedesktop.UPower", "/org/freedesktop/UPower",
                                 "org.freedesktop.UPower", "OnBattery")
        policy = load_policy()
        desired = policy.get("batteryProfile" if battery else "acProfile",
                             "power-saver" if battery else "performance")
        if desired not in ("power-saver", "balanced", "performance"):
            raise ValueError("Unsupported power profile")
        if battery != last_battery or policy != last_policy:
            profile = property_value("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles",
                                     "net.hadess.PowerProfiles", "ActiveProfile")
            if desired != profile:
                subprocess.run(["powerprofilesctl", "set", desired], check=True, timeout=5)
                print(f"Power policy applied: {desired}", flush=True)
            last_battery, last_policy = battery, policy
        mode = str(policy.get("refreshMode", "auto"))
        if mode not in ("auto", "60", "120"):
            raise ValueError("Unsupported display refresh policy")
        rate = (60 if battery else 120) if mode == "auto" else int(mode)
        monitors = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"], text=True, timeout=5))
        panel = next((m for m in monitors if m["name"].startswith("eDP-")), None)
        if panel and abs(panel["refreshRate"] - rate) > 0.5:
            code = ('hl.monitor({ output = %s, mode = "%dx%d@%d", '
                    'position = "%dx%d", scale = %s, transform = %d })') % (
                json.dumps(panel["name"]), panel["width"], panel["height"], rate,
                panel["x"], panel["y"], panel["scale"], panel["transform"])
            subprocess.run(["hyprctl", "eval", code], check=True, timeout=5)
            print(f"Laptop display set to {rate} Hz", flush=True)
    except (GLib.Error, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Power/display update deferred: {error}", flush=True)
    return GLib.SOURCE_CONTINUE


for service, path in (("org.freedesktop.UPower", "/org/freedesktop/UPower"),
                      ("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles")):
    bus.signal_subscribe(service, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                         path, None, Gio.DBusSignalFlags.NONE, update)
GLib.timeout_add_seconds(30, update)
update()
GLib.MainLoop().run()
