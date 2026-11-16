# Zephyr

Compact desktop controls for the ASUS Zephyrus G14. The collapsed widget shows battery, CPU/GPU temperature and fan speeds. Open controls to adjust supported power, display, fan and lighting settings.

Build with `bin/build`; run backend and interface checks with `bin/test`; install with `bin/install`. Launch `zephyr` from the app launcher. `zephyr status --json` reads telemetry without opening the panel.

| Key | Action |
| --- | --- |
| Space | Refresh |
| Escape | Collapse controls |
| ? | Show help |
| Q | Quit |

The user service `zephyr.service` starts the widget at login. Stop it with `systemctl --user stop zephyr`; disable startup with `systemctl --user disable zephyr`.

Hardware capabilities and limits are documented in HARDWARE.md. Firmware power-limit controls are unavailable on this model. GPU changes require reboot; unknown telemetry displays a dash. CPU boost uses a narrowly scoped, authenticated helper. Fan curves require eight increasing temperature points and a final 100% speed.

Power/display automation reads `~/.local/state/zephyr/policy.json` using `~/.local/bin/laptop-refresh.py`. Its pre-install version is preserved under `backups/`. Opening the widget reads hardware; changes require interaction. Automated checks cover validation and interface interactions, not every physical hardware write.
