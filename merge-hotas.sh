#!/usr/bin/env bash
#
# merge-hotas.sh — Virtual HOTAS multiplexer
#
# Merges two physical flight controllers into ONE virtual joystick so that
# legacy games (which only bind to a single controller) can use the whole setup:
#
#   * VKB-Sim Gladiator NXT R  (USB 231d:0200)  -> stick
#   * Thrustmaster TWCS Throttle (USB 044f:b687) -> throttle
#
# Uses evsieve to read both real devices with EXCLUSIVE access (grab), so the
# game sees only the merged virtual device.
#
# Virtual axis layout (9 analog axes + 2 POV-as-buttons):
#   X   (0)  = VKB roll                Rz       (5) = TWCS rudder rocker
#   Y   (1)  = VKB pitch               Throttle (6) = VKB zoom (solo-throttle)
#   Z   (2)  = TWCS throttle           Rudder   (7) = VKB grip twist
#   Rx  (3)  = TWCS mini-stick X       Wheel    (8) = TWCS trim (native games only*)
#   Ry  (4)  = TWCS mini-stick Y
#   POV0 -> buttons 31-34 (VKB hat U/R/D/L)   POV1 -> buttons 35-38 (TWCS hat U/R/D/L)
#
#   * DirectInput/Proton exposes only 8 axes, so it shows codes 0-7 and drops
#     Wheel (trim). Native/SDL2 games see all 9.
#
# Needs root (writes /dev/uinput, grabs the devices).
#   Manual:   sudo ./merge-hotas.sh
#   Service:  systemd/virtual-hotas.service
#
set -euo pipefail

# --- evsieve binary: prefer installed copy, fall back to local build ---
EVSIEVE="${EVSIEVE:-/usr/local/bin/evsieve}"
if [ ! -x "$EVSIEVE" ]; then
    EVSIEVE="$(dirname "$(readlink -f "$0")")/evsieve/target/release/evsieve"
fi
[ -x "$EVSIEVE" ] || { echo "evsieve binary not found" >&2; exit 1; }

# --- Physical devices (friendly udev symlinks, fall back to stable by-path) ---
VKB=/dev/input/vkb-stick
[ -e "$VKB" ] || VKB=/dev/input/by-path/pci-0000:0c:00.0-usb-0:9:1.0-event-joystick   # VKB Gladiator NXT R

TWCS=/dev/input/twcs-throttle
[ -e "$TWCS" ] || TWCS=/dev/input/by-path/pci-0000:0c:00.0-usb-0:8:1.0-event-joystick # Thrustmaster TWCS

for d in "$VKB" "$TWCS"; do
    [ -e "$d" ] || { echo "Input device not found: $d (plugged in?)" >&2; exit 1; }
done

args=(
    --input "$VKB"  domain=vkb  grab=force persist=reopen
    --input "$TWCS" domain=twcs grab=force persist=reopen

    # ---- VKB axes: roll=X, pitch=Y pass through; twist(rz)->Rudder, zoom(z)->Throttle ----
    --block abs:rx@vkb abs:ry@vkb abs:throttle@vkb abs:rudder@vkb
    --map abs:rz@vkb abs:rudder
    --map abs:z@vkb  abs:throttle

    # ---- TWCS axes: throttle(z) & rocker(rz) pass through; mini-stick->Rx/Ry; trim(rudder)->Wheel ----
    --block abs:rx@twcs abs:ry@twcs abs:throttle@twcs
    --map abs:x@twcs      abs:rx
    --map abs:y@twcs      abs:ry
    --map abs:rudder@twcs abs:wheel

    # ---- POV hats -> buttons (more broadly compatible than a 2nd hat axis) ----
    # VKB hat  -> btn 718..721 (Up/Right/Down/Left) = joystick buttons ~31-34
    --copy abs:hat0y:-1@vkb      btn:%718:1
    --copy abs:hat0y:-1..0~@vkb  btn:%718:0
    --copy abs:hat0x:1@vkb       btn:%719:1
    --copy abs:hat0x:1..~0@vkb   btn:%719:0
    --copy abs:hat0y:1@vkb       btn:%720:1
    --copy abs:hat0y:1..~0@vkb   btn:%720:0
    --copy abs:hat0x:-1@vkb      btn:%721:1
    --copy abs:hat0x:-1..0~@vkb  btn:%721:0
    # TWCS hat -> btn 722..725 (Up/Right/Down/Left) = joystick buttons ~35-38
    --copy abs:hat0y:-1@twcs     btn:%722:1
    --copy abs:hat0y:-1..0~@twcs btn:%722:0
    --copy abs:hat0x:1@twcs      btn:%723:1
    --copy abs:hat0x:1..~0@twcs  btn:%723:0
    --copy abs:hat0y:1@twcs      btn:%724:1
    --copy abs:hat0y:1..~0@twcs  btn:%724:0
    --copy abs:hat0x:-1@twcs     btn:%725:1
    --copy abs:hat0x:-1..0~@twcs btn:%725:0
    # drop the raw hat axes so they don't also appear as axes
    --block abs:hat0x@vkb abs:hat0y@vkb abs:hat0x@twcs abs:hat0y@twcs
)

# ---- TWCS buttons 288..301 -> 744..757 (avoid clash with VKB's 288..303) ----
for i in $(seq 0 13); do
    args+=( --map "btn:%$((288 + i))@twcs" "btn:%$((744 + i))" )
done

args+=(
    --output name="Virtual HOTAS (VKB NXT + TWCS)" \
             create-link=/dev/input/by-id/virtual-hotas-event-joystick \
             repeat=disable
)

echo "Merging  stick=$VKB  throttle=$TWCS  -> /dev/input/by-id/virtual-hotas-event-joystick"
exec "$EVSIEVE" "${args[@]}"
