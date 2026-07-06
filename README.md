# Controller Multiplexer — Virtual HOTAS

Merge two physical flight controllers into **one virtual joystick**, so legacy
flight sims (which only bind to a single controller) can use the whole setup.

Built on [**evsieve**](https://github.com/KarsMulder/evsieve) (evdev → uinput).

## This machine's setup

| Physical device | USB ID | Role |
|---|---|---|
| VKB-Sim Gladiator NXT R | `231d:0200` | Stick — roll / pitch / twist / zoom / hat / buttons |
| Thrustmaster TWCS Throttle | `044f:b687` | Throttle — throttle / rocker / trim / mini-stick / hat / buttons |

An ASRock LED Controller (`26ce:01a2`) also mis-registers as a joystick; the udev
rule de-classifies it (`ID_INPUT_JOYSTICK=0`) so SDL/Steam/Proton/native games
ignore it. (Its kernel `js0` node still exists for legacy `js`-only apps.)

## Merge mapping

10 analog axes + both POV hats as buttons:

| Code | Virtual axis | Source | Notes |
|---|---|---|---|
| 0 | X | VKB roll | |
| 1 | Y | VKB pitch | |
| 2 | Z | TWCS throttle (16-bit) | |
| 3 | Rx | TWCS mini-stick X | |
| 4 | Ry | TWCS mini-stick Y | |
| 5 | Rz | TWCS rudder rocker | |
| 6 | Throttle | VKB zoom (solo-throttle) | |
| 7 | Rudder | VKB grip twist | |
| 8 | Wheel | TWCS trim | **native/SDL2 only** — see note |
| 9 | Gas | VKB trigger (also button 1) | **native/SDL2 only** — 10th axis |

**DirectInput 8-axis limit:** Proton/DirectInput games expose only 8 axes
(codes 0–7), so they'll see everything **except trim (Wheel) and the
trigger-axis (Gas)**. Native/SDL2 games see all 10. To change which axes take
priority for Proton, edit the axis maps in `merge-hotas.sh`.

**Trigger as axis:** the VKB trigger drives **both button 1 and the Gas axis**
(via `--copy` — one input, two outputs), for games that read a trigger as an
analog axis (gamepad style).

**POV hats → buttons** (more broadly compatible than a 2nd hat axis):
- VKB hat → buttons ~31–34 (Up/Right/Down/Left, codes 718–721)
- TWCS hat → buttons ~35–38 (codes 722–725)

**Buttons:** VKB buttons keep their low numbers (1–16 primary, 17–30 extended);
TWCS's 14 buttons are shifted to ~57–70 (codes 744–757) to avoid colliding with
the VKB's. There are cosmetic gaps in the button numbering (advertised-but-unused
codes) — harmless.

## Files

- `merge-hotas.sh` — the evsieve invocation (the actual merge). Runnable directly.
- `systemd/virtual-hotas.service` — runs the merge at boot / on hotplug.
- `udev/99-virtual-hotas.rules` — de-classify the ASRock, add stable symlinks
  (`/dev/input/vkb-stick`, `/dev/input/twcs-throttle`), trigger the service.
- `evsieve/` — upstream evsieve source (built to `evsieve/target/release/evsieve`).

## Install

From a fresh clone, first fetch and build the evsieve submodule:

```bash
git submodule update --init
cargo build --release --manifest-path evsieve/Cargo.toml
```

Then install everything (already done on this machine):

```bash
sudo install -m 755 evsieve/target/release/evsieve /usr/local/bin/evsieve
sudo modprobe uinput
echo uinput | sudo tee /etc/modules-load.d/uinput.conf
sudo install -m 644 systemd/virtual-hotas.service /etc/systemd/system/
sudo install -m 644 udev/99-virtual-hotas.rules /etc/udev/rules.d/
sudo systemctl daemon-reload
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=input --action=add
sudo systemctl enable --now virtual-hotas.service
```

## Operate

```bash
systemctl status virtual-hotas.service      # health
sudo systemctl restart virtual-hotas.service # after editing merge-hotas.sh
sudo systemctl stop virtual-hotas.service    # release the sticks (use them normally)
jstest-gtk                                   # visual test of the merged device
evtest /dev/input/by-id/virtual-hotas-event-joystick
```

## Steam / Proton notes

- Steam Input is gamepad-oriented and would drop most axes — leave it **off** for
  this virtual stick and let the game read it directly (DirectInput).
- The two physical sticks are grabbed by evsieve, so nothing else receives their
  input even if they still appear in a device list.
- Proton/DirectInput shows 8 axes (no trim); native games show all 9.

## Uninstall

```bash
sudo systemctl disable --now virtual-hotas.service
sudo rm /etc/systemd/system/virtual-hotas.service /etc/udev/rules.d/99-virtual-hotas.rules
sudo rm -f /usr/local/bin/evsieve /etc/modules-load.d/uinput.conf
sudo systemctl daemon-reload && sudo udevadm control --reload && sudo udevadm trigger
```
