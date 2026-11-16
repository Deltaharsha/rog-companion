# Zephyrus hardware contract

Audited 2026-11-16 on ROG Zephyrus G14 GA403UP / GA403UP_GA403UP, asusctl/asusd 6.5.0. These are observed host capabilities; write forms below come from installed CLI help and were not exercised except the keyboard power probe noted at the end.

## Process contract

Use QProcess argument lists (no shell). `asusctl` writes logs and human output to stdout and can **exit 0 even when D-Bus connection fails**. Check output/errors and re-read the affected value; exit status alone is insufficient. In the Codex sandbox system D-Bus access needs escalation, while normal desktop apps should use the system bus directly. Do not use sudo in the app.

| Feature | Read | Write contract / values |
|---|---|---|
| Performance profile | `asusctl profile list`; `asusctl profile get` | `asusctl profile set Quiet\|Balanced\|Performance`. `-a` sets AC preference, `-b` battery preference. Get returns active plus AC/battery profiles separately. |
| Profile tuning | `asusctl profile tuning` | `asusctl profile tuning true\|false`; observed false. Enabling does not make unsupported limits work. |
| Fan curves | `asusctl fan-curve --mod-profile performance` (also quiet/balanced); `--get-enabled` reads active fan states | `asusctl fan-curve --mod-profile performance --fan cpu --data '30c:0%,40c:10%,50c:20%,60c:35%,70c:50%,80c:70%,90c:90%,100c:100%'`. Exactly eight points; selectors cpu/gpu/mid. Without `%`, PWM is raw 0–255. `--enable-fan-curve true\|false` needs both profile/fan; `--enable-fan-curves true\|false` needs profile. `--default` resets the **active** profile. Re-read profile after writes. |
| Charge limit | `asusctl battery info` | `asusctl battery limit N`, 20–100. `asusctl battery oneshot [N]` defaults to 100. Current limit 95%; sysfs `charge_control_end_threshold` agrees. |
| Keyboard brightness | `asusctl leds get` | `asusctl leds set off\|low\|med\|high`; also `next`/`prev`. Native brightness is 0–3. |
| Keyboard effects | CLI bare `asusctl aura effect` reports available modes but no current color getter; use D-Bus below | Only Static, Breathe, Pulse advertised on this host. `asusctl aura effect static --colour ff00ff`; `pulse --colour ff00ff`; `breathe --colour ff00ff --colour2 0000ff --speed low\|med\|high`. No per-zone support advertised. |
| Keyboard LED power | D-Bus `LedPower` | `asusctl aura power keyboard [--boot] [--awake] [--sleep] [--shutdown]`. **Omitted flags are false; even a bare command writes all false.** Supply the complete desired flag set. |
| Slash lighting | `asusctl slash get`; `asusctl slash list` | `asusctl slash set --enable` or `--disable`; `--brightness 0..255`, `--interval 0..5`, `--mode NAME`; `--show-on-boot true\|false`, `--show-on-shutdown`, `--show-on-sleep`, `--show-on-battery`, `--show-battery-warning` all take booleans. |
| Boot sound | `asusctl armoury get boot_sound` | `asusctl armoury set boot_sound 0\|1`; observed 1. |
| GPU firmware | `asusctl armoury get gpu_mux_mode`; `... dgpu_disable` | `asusctl armoury set PROPERTY 0\|1` exists. Both firmware readings currently 0; do not claim mode transition succeeded without re-reading actual and queued state. Full G-Helper mode orchestration unverified; supergfxctl is absent. |
| Display brightness | `brightnessctl -c backlight -m info` | `brightnessctl -c backlight set 50%`. Current device nvidia_0, range 0–100. Explicit class avoids selecting keyboard/lock LEDs. |
| Wi-Fi | `nmcli -t -f WIFI radio` -> enabled/disabled | `nmcli radio wifi on\|off`. Installed, NetworkManager responds. |
| Bluetooth | `bluetoothctl show` -> Powered yes/no; avoid presenting controller address | `bluetoothctl power on\|off`. Installed and controller responds. |

Slash animations returned: Static, Bounce, Slash, Loading, BitStream, Transmission, Flow, Flux, Phantom, Spectrum, Hazard, Interfacing, Ramp, GameOver, Start, Buzzer. Current state: enabled, brightness 255, interval 0, Bounce, all CLI-visible power flags true. There is no Anime interface on this machine: hide AniMe Matrix controls despite CLI help existing.

## Firmware limits: currently unavailable

Under `/sys/class/firmware-attributes/asus-armoury/attributes/`, `nv_dynamic_boost`, `nv_temp_target`, `nv_tgp`, `ppt_pl1_spl`, `ppt_pl2_sppt`, `ppt_pl3_fppt` exist, with scalar_increment 1, but **min_value, max_value, default_value and current_value all fail ENODEV (19)**. `asusctl armoury list` calls them unavailable. Disable/hide numeric limit sliders; never invent ranges. `nv_base_tgp/current_value` reads 55, with no min/max/default metadata; treat as read-only base TGP. `charge_mode` enumerates 0;1;2 (observed 1); its description is “Show the current mode of charging”, so do not expose a write control without a documented meaning. `boot_sound`, `dgpu_disable`, `gpu_mux_mode` enumerate 0;1 with no min/max/default metadata. `pending_reboot` is a file, not an attribute directory, and currently reads 0.

## Native D-Bus for reliable readback

Service `xyz.ljones.Asusd`, system bus; standard `org.freedesktop.DBus.Properties.Get/GetAll/Set` and `PropertiesChanged`.

* `/xyz/ljones`, interface `xyz.ljones.Platform`: PlatformProfile u (Balanced=0, Performance=1, Quiet=2), PlatformProfileChoices au, PlatformProfileOnAc/OnBattery u, ChargeControlEndThreshold y, EnablePptGroup b; writable properties emit changes. Observed choices [2,0,1]. CLI get confirms profile mapping.
* Same path, `xyz.ljones.FanCurves`: `FanCurveData(u profile) -> a(s(yyyyyyyy)(yyyyyyyy)b)` = fan name, eight raw PWM bytes, eight temperature bytes, enabled. `SetFanCurve(u,(s(yyyyyyyy)(yyyyyyyy)b))`; `SetFanCurvesEnabled(u,b)`; `SetProfileFanCurveEnabled(u,s,b)`; `SetCurvesToDefaults(u)`.
* Discover Aura paths via introspection rather than hardcoding USB instance. Current `/xyz/ljones/aura/19b6_5_4` has BOTH `xyz.ljones.Aura` and `xyz.ljones.Slash`.
* Aura properties: Brightness u; LedMode u; LedModeData `(uu(yyy)(yyy)ss)` = effect, zone, RGB1, RGB2, speed, direction; LedPower `(a(ubbbb))` = list of zone + boot/awake/sleep/shutdown; SupportedBasicModes au, SupportedBasicZones au, SupportedBrightness au, SupportedPowerZones au. `AllModeData() -> a{u(uu(yyy)(yyy)ss)}` returns presets. Host advertises basic modes [0,1,10], while saved preset map has keys [0,1,9]; prefer CLI labels for supported choices and do not assume enum 9/10 equivalence without source verification.
* Slash: Enabled b; Brightness y; Interval y; Mode y; ShowOnBoot/Shutdown/Sleep/Battery/LidClosed and ShowBatteryWarning b. CLI `get` omits ShowOnLidClosed. Read properties after CLI writes.
* `/xyz/ljones/asus_armoury/PROPERTY`, `xyz.ljones.AsusArmoury`: CurrentValue i; PossibleValues ai; MinValue/MaxValue/DefaultValue/ScalarIncrement i; AvailableAttrs as; QueuedGpuValue i; ApplyQueuedGpuValue() -> b. Metadata unavailable is -1 at D-Bus layer. GPU MUX has CurrentValue 0 and QueuedGpuValue 1 while pending_reboot=0; represent actual/queued separately. dgpu_disable queued value is -1. Do not interpret a queued value as the active mode.

## Sensors

Discover hwmon directories by `name` every run (indices can change).

| hwmon name | Files | Units / meaning |
|---|---|---|
| k10temp | temp1_input; temp1_label=Tctl | millidegrees C, CPU temperature |
| asus | fan1/2/3_input and labels cpu_fan/gpu_fan/mid_fan | RPM; mid fan currently 0 is a valid reading |
| amdgpu | temp1_input (edge); power1_input (PPT); freq1_input (sclk) | millidegrees C, microwatts, Hz; these describe AMD graphics/APU, not NVIDIA dGPU |
| nvme | temp1/2_input labels Composite/Sensor 1 | millidegrees C |
| asus_custom_fan_curve | pwmN_auto_pointM_temp/pwm, pwmN_enable | fan N 1=CPU,2=GPU,3=MID; M=1..8; temperatures already Celsius, PWM 0–255. Observed enable 1 for custom CPU, 2 for automatic GPU/MID. Prefer daemon writes. |

NVIDIA `nvidia-smi` currently fails to communicate with the NVIDIA driver. Treat dGPU telemetry as unavailable, never zero or AMD readings. `/sys/class/power_supply/BAT1/` supplies capacity (percent), status, current_now (microamps), voltage_now (microvolts), charge_now/full/full_design (microamp-hours), cycle_count, and charge_control_end_threshold. Compute battery watts as current_now × voltage_now / 1e12, using status for charge/discharge direction; this battery does not provide power_now or energy_now. `/sys/class/power_supply/ACAD/online` is AC state. `/sys/class/rfkill/*/{type,hard,soft}` exposes wlan/bluetooth blocks even though `/dev/rfkill` is unavailable inside the execution sandbox.

Audit correction: a bare `asusctl aura power keyboard` probe temporarily cleared four LED flags. They were immediately restored using all four flags and D-Bus confirmed exactly the original true/true/true/true state. No other setting writes were exercised.
