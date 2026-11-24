# Fix: restart hangs after switching to Eco

**Affects:** asusd (tested with asusctl 6.5.0) on laptops where the desktop uses the NVIDIA GPU in Hybrid mode. After switching Hybrid → Eco (Integrated), the restart freezes on the shutdown splash and you have to hold the power button.

**Cause:** asusd's `asus-shutdown.service` applies the queued GPU change as soon as the restart is requested. At that point the desktop is still running on the NVIDIA GPU. The helper turns the GPU off anyway, `nvidia_modeset` oopses (`BUG ... ReleaseOwnership`), and the shutdown never finishes.

**Fix:** `asus-gpu-late-apply.service` replaces that helper. On shutdown it waits until the display manager and all user sessions have stopped. It then unloads the NVIDIA driver and asks asusd to apply the queued change. If the driver can't be unloaded, it skips Eco and lets the restart finish in the current mode.

## Install

```sh
sudo install -Dm755 asus-gpu-late-apply /usr/local/lib/asus-gpu-late-apply
sudo install -Dm644 asus-gpu-late-apply.service /etc/systemd/system/asus-gpu-late-apply.service
sudo systemctl daemon-reload
sudo systemctl mask asus-shutdown.service
sudo systemctl enable --now asus-gpu-late-apply.service
```

After your next GPU switch, check what it did with `journalctl -b -1 -t asus-gpu-late-apply`. A successful Eco switch logs:

```
queued: gpu_mux_mode=-1 dgpu_disable=1
NVIDIA driver unloaded
applying dgpu_disable = 1
applied dgpu_disable = 1
```

To undo: `sudo systemctl disable --now asus-gpu-late-apply.service && sudo systemctl unmask asus-shutdown.service`.

Verified on the ROG Zephyrus G14 GA403UP (RTX 5070 Laptop, nvidia-open 615.78) through real Hybrid → restart and Eco → restart cycles.
