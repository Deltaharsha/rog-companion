# ROG Companion

**An ASUS ROG laptop control panel for Linux.** Fans, performance mode, battery charge limit, GPU mode, keyboard and Slash lighting, all in a compact panel that sits on your desktop. Think G-Helper, built for Hyprland and Omarchy.

<p>
  <img src="docs/panel.png" width="300" alt="ROG Companion panel showing battery, CPU and GPU temperatures and fan speeds">
  <img src="docs/controls.png" width="300" alt="ROG Companion with controls open">
</p>

> Unofficial community project. Not made by or affiliated with ASUS. "ROG" is a trademark of ASUSTeK Computer Inc.

## What it does

- **Live status:** battery, charge rate, battery health, CPU/GPU temperature and all fan speeds at a glance
- **Performance:** Silent / Balanced / Turbo, plus separate profiles for battery and plugged in
- **Battery care:** charge limit (20–100%) and one-off charge to 100%
- **Fans:** custom fan curves per profile, with validation so you can't set an unsafe curve
- **GPU mode:** Hybrid, Integrated (Eco) or NVIDIA (Ultimate), queued safely for the next reboot
- **Display:** brightness, and automatic refresh rate (e.g. 60 Hz on battery, 120 Hz plugged in) using whatever rates your panel supports
- **Lighting:** keyboard brightness, effect and colour, keyboard power states, and Slash bar settings on models that have one
- **CPU boost** on/off through a tiny, audited root helper that can only write that one setting

Every change is **read back from the hardware** and reported as verified or not, so the panel never claims something worked when it didn't.

It follows your Omarchy theme and language live, and works on any Wayland desktop with layer-shell support.

## Supported laptops

ROG Companion talks to [`asusctl`/`asusd`](https://asus-linux.org), so it supports the ROG and TUF laptops that `asusctl` supports. It shows only the controls your model actually has.

| Model | Status |
|---|---|
| ROG Zephyrus G14 (GA403UP, 2024) | ✅ Tested daily |
| Other ROG Zephyrus / Strix / Flow / TUF | 🧪 Should work. [Tell us how it goes!](https://github.com/Deltaharsha/rog-companion/issues/new?title=Tested+on+MODEL&body=Model:%0A%0AWhat+worked:%0A%0AWhat+didn't:%0A%0AOutput+of+%60rog-companion+status%60+and+%60rog-companion+controls%60:%0A) |

## Install

### Arch / Omarchy (AUR)

```sh
yay -S rog-companion
systemctl --user enable --now rog-companion.service rog-companion-policy.service
```

### From source

Needs `asusctl`, Qt 6 (base, declarative, wayland), `layer-shell-qt`, `power-profiles-daemon`, `brightnessctl`, `upower` and `python-gobject`.

```sh
git clone https://github.com/Deltaharsha/rog-companion
cd rog-companion
bin/install   # builds, tests and installs it as a package
systemctl --user enable --now rog-companion.service rog-companion-policy.service
```

## Use

The panel starts at login and sits in the bottom-right corner. Click **Open controls**, or launch **ROG Companion** from your app launcher to bring it forward.

| Key | Action |
|---|---|
| Space | Refresh |
| Escape | Close controls |
| ? | Show shortcuts |
| Q | Quit |

From a terminal or script:

```sh
rog-companion status            # all readings as JSON
rog-companion controls          # every control, and why any are unavailable on your model
rog-companion set charge 80     # change a setting; prints JSON, exits 0 or 1
```

## Good to know

- **Settings change only when you press Apply.** Opening the panel never writes to your hardware.
- **GPU mode changes need a reboot.** The panel shows what's queued separately from what's active.
- **Fan curves** need eight points with rising temperatures, ending at 100% speed.
- **Firmware power limits** are shown for reference when your laptop reports them. Changing them isn't supported yet.
- Hardware details for the tested model are in [HARDWARE.md](HARDWARE.md).

## Development

```sh
bin/build    # build into build/
bin/test     # backend and interface tests, offscreen
bin/install  # package and install this working copy
```

C++ owns the hardware logic (`src/backend.cpp`), QML owns the layout (`src/Main.qml`). Translations live in `src/i18n/`.

## Support the project

ROG Companion is free and open source. If it saves you from booting into Windows for Armoury Crate, a ⭐ on GitHub helps other ROG owners find it. Also check out [dotdoctor](https://github.com/Deltaharsha/dotdoctor), a checkup tool for your Linux desktop config.

## License

MIT
