# Restart hang after switching to Eco

**Affects:** asusd (tested with asusctl 6.5.0) on laptops where the desktop uses the NVIDIA GPU in Hybrid mode. After switching Hybrid → Eco (Integrated), the restart freezes on the shutdown splash and you have to hold the power button.

**Cause:** asusd's `asus-shutdown.service` applies the queued GPU change as soon as the restart is requested. At that point the desktop is still running on the NVIDIA GPU. The helper turns the GPU off anyway, `nvidia_modeset` oopses (`BUG ... ReleaseOwnership`), and the shutdown never finishes.

**Fix:** `asus-gpu-late-apply.service` replaces that helper. On shutdown it waits until the display manager and all user sessions have stopped. It then unloads the NVIDIA driver and asks asusd to apply the queued change. If the driver can't be unloaded, it skips Eco and lets the restart finish in the current mode.

Verified on the ROG Zephyrus G14 GA403UP (RTX 5070 Laptop, nvidia-open 615.78) through real Hybrid → restart and Eco → restart cycles.

## In the ROG Companion package (0.3.1 and later)

Nothing to do. The package installs:

| File | Purpose |
|---|---|
| [`/usr/lib/rog-companion/asus-gpu-late-apply`](../../src/asus-gpu-late-apply) | Applies the queue late in shutdown |
| [`/usr/lib/systemd/system/asus-gpu-late-apply.service`](../../pkgbuild/systemd/asus-gpu-late-apply.service) | Runs it, always enabled |
| [`/usr/lib/systemd/system/asus-shutdown.service.d/rog-companion.conf`](../../pkgbuild/systemd/asus-shutdown-rog-companion.conf) | Keeps `asus-shutdown` from starting while the package is installed |

Removing the package hands GPU changes back to `asus-shutdown`.

After your next GPU switch, check what happened with `journalctl -b -1 -t asus-gpu-late-apply`. A successful Eco switch logs:

```
queued: gpu_mux_mode=-1 dgpu_disable=1
NVIDIA driver unloaded
applying dgpu_disable = 1
applied dgpu_disable = 1
```

**Opt out** (go back to `asus-shutdown`):

```sh
sudo mkdir -p /etc/systemd/system/asus-shutdown.service.d
sudo ln -s /dev/null /etc/systemd/system/asus-shutdown.service.d/rog-companion.conf
sudo systemctl mask asus-gpu-late-apply.service
sudo systemctl daemon-reload
```

**Installed the manual fix from the 0.3.0 release?** Remove it once you're on 0.3.1:

```sh
sudo rm -f /etc/systemd/system/asus-gpu-late-apply.service /etc/systemd/system/multi-user.target.wants/asus-gpu-late-apply.service /usr/local/lib/asus-gpu-late-apply
sudo systemctl unmask asus-shutdown.service
```

## Without ROG Companion

The fix works with plain asusctl too. From a checkout of this repo:

```sh
sudo install -Dm755 src/asus-gpu-late-apply /usr/local/lib/asus-gpu-late-apply
sed 's|/usr/lib/rog-companion/|/usr/local/lib/|' pkgbuild/systemd/asus-gpu-late-apply.service | sudo tee /etc/systemd/system/asus-gpu-late-apply.service >/dev/null
sudo ln -sf ../asus-gpu-late-apply.service /etc/systemd/system/multi-user.target.wants/asus-gpu-late-apply.service
sudo systemctl daemon-reload
sudo systemctl mask asus-shutdown.service
sudo systemctl stop asus-shutdown.service
sudo systemctl start asus-gpu-late-apply.service
```
