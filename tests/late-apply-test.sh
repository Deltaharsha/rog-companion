#!/bin/bash
# Tests src/asus-gpu-late-apply against a fake asusd, systemctl and modprobe.
# The fake firmware refuses dgpu_disable=1 (EBUSY) while the MUX that was in
# effect at boot still routes the panel to the NVIDIA GPU, like the GA403UP.
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/src/asus-gpu-late-apply
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAKE=$WORK/fake
BIN=$WORK/bin
mkdir -p "$BIN"

cat >"$BIN/busctl" <<'EOF'
#!/bin/bash
# busctl [--timeout=N] get-property|set-property|call DEST PATH IFACE ...
[[ $1 == --timeout=* ]] && shift
verb=$1 attr=${3##*/} member=$5
echo "busctl $verb $attr $member ${*:6}" >>"$FAKE/log"
case $verb in
get-property) echo "i $(<"$FAKE/$attr.$member")" ;;
set-property) echo "$7" >"$FAKE/$attr.QueuedGpuValue" ;; # asusd queues GPU attributes
call)
	[[ -e $FAKE/$attr.fail ]] && exit 1
	q=$(<"$FAKE/$attr.QueuedGpuValue")
	[[ $q == -1 ]] && exit 1
	if [[ $attr == dgpu_disable && $q == 1 && $(<"$FAKE/mux_at_boot") == 0 ]]; then
		echo "Call failed: Device or resource busy (os error 16)" >&2
		exit 1
	fi
	if [[ $attr == dgpu_disable && $q == 1 && -d $FAKE/root/sys/module/nvidia ]]; then
		echo "GPU REMOVED WHILE THE NVIDIA DRIVER WAS LOADED" >>"$FAKE/log"
	fi
	if [[ $attr == gpu_mux_mode ]]; then
		echo "$q" >"$FAKE/mux_next_boot"
	else
		echo "$q" >"$FAKE/$attr.CurrentValue"
	fi
	echo -1 >"$FAKE/$attr.QueuedGpuValue"
	;;
esac
EOF
cat >"$BIN/systemctl" <<'EOF'
#!/bin/bash
case $1 in
is-system-running) cat "$FAKE/system_state" ;;
is-active) exit 1 ;;
esac
EOF
# Fake plymouthd: while $FAKE/plymouthd exists it holds the NVIDIA DRM node,
# like the real splash at boot. Only `plymouth quit` releases it.
# pidof never finds it: on the GA403UP (boot 753ae3e8, 2026-11-26 15:36) the
# real pidof missed the running boot splash, so the script must not rely on it.
printf '#!/bin/sh\nexit 1\n' >"$BIN/pidof"
cat >"$BIN/plymouth" <<'EOF'
#!/bin/bash
[[ -e $FAKE/plymouthd ]] || exit 1 # no daemon: every command fails
echo "plymouth $*" >>"$FAKE/log"
[[ $1 == quit ]] && rm -f "$FAKE/plymouthd"
exit 0
EOF
cat >"$BIN/modprobe" <<'EOF'
#!/bin/bash
[[ -e $FAKE/nvidia_busy || -e $FAKE/plymouthd ]] && exit 1
rm -rf "$FAKE/root/sys/module/nvidia"
EOF
for stub in fuser sleep; do printf '#!/bin/sh\nexit 1\n' >"$BIN/$stub"; done
chmod +x "$BIN"/*

failures=0
check() { # description, expected, actual
	if [[ $2 == "$3" ]]; then
		echo "ok   $1"
	else
		echo "FAIL $1: expected '$2', got '$3'"
		failures=$((failures + 1))
	fi
}

# boot MUX DGPU: a fresh boot in the given mode, with the NVIDIA driver loaded.
boot() {
	rm -rf "$FAKE"
	mkdir -p "$FAKE/root/sys/module/nvidia" "$FAKE/state"
	echo "$1" >"$FAKE/gpu_mux_mode.CurrentValue"
	echo "$2" >"$FAKE/dgpu_disable.CurrentValue"
	echo "$1" >"$FAKE/mux_at_boot"
	echo -1 >"$FAKE/gpu_mux_mode.QueuedGpuValue"
	echo -1 >"$FAKE/dgpu_disable.QueuedGpuValue"
	: >"$FAKE/log"
}
# reboot: keep the firmware values and the state directory, lose asusd's queue.
reboot() {
	if [[ -e $FAKE/mux_next_boot ]]; then
		mv "$FAKE/mux_next_boot" "$FAKE/gpu_mux_mode.CurrentValue"
	fi
	cp "$FAKE/gpu_mux_mode.CurrentValue" "$FAKE/mux_at_boot"
	echo -1 >"$FAKE/gpu_mux_mode.QueuedGpuValue"
	echo -1 >"$FAKE/dgpu_disable.QueuedGpuValue"
	mkdir -p "$FAKE/root/sys/module/nvidia"
}
queue() { echo "$2" >"$FAKE/$1.QueuedGpuValue"; }
run() { # system state, args...
	echo "$1" >"$FAKE/system_state"
	shift
	PATH=$BIN:$PATH FAKE=$FAKE STATE_DIRECTORY=$FAKE/state ASUS_GPU_LATE_APPLY_SYSROOT=$FAKE/root \
		bash "$SCRIPT" "$@" >>"$FAKE/out" 2>&1
}
mode() { echo "mux=$(<"$FAKE/gpu_mux_mode.CurrentValue") dgpu=$(<"$FAKE/dgpu_disable.CurrentValue")"; }
marker() { [[ -e $FAKE/state/finish-eco-at-boot ]] && echo yes || echo no; }
unsafe() { grep -c "REMOVED WHILE" "$FAKE/log"; }

echo "# Ultimate -> Integrated takes one restart"
boot 0 0
queue gpu_mux_mode 1
queue dgpu_disable 1
run stopping
check "shutdown helper succeeds" 0 "$?"
check "routing remains on NVIDIA until reboot" "mux=0 dgpu=0" "$(mode)"
check "shutdown leaves the marker" yes "$(marker)"
check "shutdown never tries dgpu_disable=1" 0 "$(grep -c 'call dgpu_disable' "$FAKE/log")"
reboot
run starting --boot
check "boot finishes Eco" "mux=1 dgpu=1" "$(mode)"
check "boot removes the marker" no "$(marker)"
check "boot unloads NVIDIA first" 0 "$(unsafe)"
: >"$FAKE/log"
run starting --boot
check "the following boot does nothing" "" "$(<"$FAKE/log")"

echo "# Boot splash holds the NVIDIA GPU (seen on the GA403UP, 2026-11-26)"
boot 1 0
: >"$FAKE/state/finish-eco-at-boot"
: >"$FAKE/plymouthd"
run starting --boot
check "Eco finished" "mux=1 dgpu=1" "$(mode)"
check "splash ended, keeping its last frame" 1 "$(grep -c 'plymouth quit --retain-splash' "$FAKE/log")"
check "NVIDIA unloaded first" 0 "$(unsafe)"

echo "# Hybrid -> Integrated is unchanged"
boot 1 0
queue dgpu_disable 1
run stopping
check "shutdown applies Eco" "mux=1 dgpu=1" "$(mode)"
check "no marker" no "$(marker)"
check "NVIDIA unloaded first" 0 "$(unsafe)"

echo "# Hybrid -> Ultimate is unchanged"
boot 1 0
queue gpu_mux_mode 0
queue dgpu_disable 0
run stopping
check "Ultimate shutdown succeeds" 0 "$?"
reboot
check "reboot applies Ultimate" "mux=0 dgpu=0" "$(mode)"
check "dGPU enabled before the MUX" "dgpu_disable gpu_mux_mode" "$(grep -o 'call [a-z_]*' "$FAKE/log" | cut -d' ' -f2 | xargs)"

echo "# Integrated -> Hybrid is unchanged"
boot 1 1
queue dgpu_disable 0
run stopping
check "shutdown applies Hybrid" "mux=1 dgpu=0" "$(mode)"

echo "# Ultimate with only Eco queued (no MUX change)"
boot 0 0
queue dgpu_disable 1
run stopping
check "Eco is skipped, nothing changes" "mux=0 dgpu=0" "$(mode)"
check "no marker" no "$(marker)"

echo "# Boot with the NVIDIA driver busy"
boot 1 0
: >"$FAKE/state/finish-eco-at-boot"
touch "$FAKE/nvidia_busy"
run starting --boot
check "GPU left on" "mux=1 dgpu=0" "$(mode)"
check "Eco queued for the next restart" 1 "$(<"$FAKE/dgpu_disable.QueuedGpuValue")"
check "marker removed" no "$(marker)"

echo "# Unit started by hand on a running desktop"
boot 1 0
: >"$FAKE/state/finish-eco-at-boot"
run running --boot
check "GPU left on" "mux=1 dgpu=0" "$(mode)"
check "Eco queued for the next restart" 1 "$(<"$FAKE/dgpu_disable.QueuedGpuValue")"
check "NVIDIA left loaded" yes "$([[ -d $FAKE/root/sys/module/nvidia ]] && echo yes || echo no)"

echo "# Marker present but the MUX is back on NVIDIA (changed elsewhere)"
boot 0 0
: >"$FAKE/state/finish-eco-at-boot"
run starting --boot
check "nothing changes" "mux=0 dgpu=0" "$(mode)"
check "marker removed" no "$(marker)"

echo "# Stop on a running desktop never applies anything"
boot 1 0
queue dgpu_disable 1
run running
check "nothing applied" "mux=1 dgpu=0" "$(mode)"

for state in unknown offline ""; do
	boot 1 0
	queue dgpu_disable 1
	run "$state"
	check "unconfirmed shutdown ($state) leaves hardware alone" "" "$(<"$FAKE/log")"
done

boot 1 1
queue dgpu_disable 0
queue gpu_mux_mode 0
touch "$FAKE/dgpu_disable.fail"
run stopping
check "failed enable preserves integrated routing" "mux=1 dgpu=1" "$(mode)"

boot 1 1
queue gpu_mux_mode 0
run stopping
check "MUX-only request requires an enabled GPU" "mux=1 dgpu=1" "$(mode)"

boot 0 0
queue gpu_mux_mode 1
queue dgpu_disable 1
touch "$FAKE/gpu_mux_mode.fail"
run stopping
check "failed MUX switch leaves NVIDIA on" "mux=0 dgpu=0" "$(mode)"
check "failed MUX switch never schedules boot removal" no "$(marker)"

boot 1 0
touch "$FAKE/state/finish-eco-at-boot"
echo -1 >"$FAKE/gpu_mux_mode.CurrentValue"
run starting --boot
check "unreadable boot routing preserves a failure record" yes "$([[ -e $FAKE/state/finish-eco-failed ]] && echo yes)"
check "unreadable boot routing leaves NVIDIA on" 0 "$(<"$FAKE/dgpu_disable.CurrentValue")"

if ((failures)); then
	echo "$failures check(s) failed"
	exit 1
fi
echo "all late-apply checks passed"
