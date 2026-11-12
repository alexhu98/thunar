#!/bin/bash
# Issues #5 and #6: -g/--geometry sets the new window's size and position, -s/--workspace opens it on workspace N.
set -euo pipefail
. .github/scripts/verify-lib.sh

for d in alpha beta gamma delta epsilon zeta; do
  mkdir -p "$WORK/$d"
done

SCREEN_W=$(xdotool getdisplaygeometry | cut -d' ' -f1)
SCREEN_H=$(xdotool getdisplaygeometry | cut -d' ' -f2)

geom() {
  local info X Y WIDTH HEIGHT left right top bottom
  info=$(xwininfo -id "$1")
  X=$(sed -n 's/.*Absolute upper-left X: *//p' <<<"$info")
  Y=$(sed -n 's/.*Absolute upper-left Y: *//p' <<<"$info")
  WIDTH=$(sed -n 's/.*Width: *//p' <<<"$info")
  HEIGHT=$(sed -n 's/.*Height: *//p' <<<"$info")
  IFS=', ' read -r left right top bottom < <(xprop -id "$1" _NET_FRAME_EXTENTS | sed 's/.*= //')
  [[ $bottom =~ ^[0-9]+$ ]] || fail "window $1 has no _NET_FRAME_EXTENTS"
  GW=$WIDTH GH=$HEIGHT
  FX=$((X - left)) FY=$((Y - top)) FW=$((WIDTH + left + right)) FH=$((HEIGHT + top + bottom))
}

near() {
  (( $1 >= $2 && $1 <= $3 )) || fail "$4 is $1, expected $2..$3"
}

remembered() { xfconf-query -c thunar -p /last-window-width 2>/dev/null || echo unset; }

find_window() {
  local i w
  for ((i = 0; i < 75; i++)); do
    w=$(xdotool search --all --pid "$THUNAR_PID" --name "^$1( |$)" 2>/dev/null | head -1) || true
    [[ -n $w ]] && { WID=$w; return 0; }
    sleep 0.2
  done
  fail "no Thunar window titled $1 within 15 s"
}

G1='Geometry'
G2='Workspace'

xfconf-query -c thunar -p /last-window-width -n -t int -s 900
xfconf-query -c thunar -p /last-window-height -n -t int -s 600
WIDTH_BEFORE=$(remembered)

open_thunar -g 1000x560+200+120 "$WORK/alpha"
wait_title "$WID" alpha
sleep 1
geom "$WID"
(( GW == 1000 && GH == 560 )) || fail "thunar -g 1000x560+200+120 opened a ${GW}x${GH} window"
near "$FX" 198 202 "the frame's x"
near "$FY" 118 122 "the frame's y"
shot root geometry-cold "With no Thunar running, thunar -g 1000x560+200+120 alpha opened alpha as a 1000x560 window whose frame starts at (200, 120)"

shot root before-negative "One Thunar window, alpha, before thunar -w -g 600x400-40-40 beta"
open_thunar -w -g 600x400-40-40 "$WORK/beta"
wait_title "$WID" beta
sleep 1
geom "$WID"
(( GW == 600 && GH == 400 )) || fail "thunar -g 600x400-40-40 opened a ${GW}x${GH} window"
near $((SCREEN_W - FX - FW)) 38 42 "the gap to the screen's right edge"
near $((SCREEN_H - FY - FH)) 38 42 "the gap to the screen's bottom edge"
shot root after-negative "With Thunar running, a second window, beta, 600x400, sits 40 px from the screen's right and bottom edges"
pair negative "Ran thunar -w -g 600x400-40-40 beta with Thunar running" "Negative offsets measure from the right and bottom edges" "one window, alpha" "beta 600x400, 40 px from bottom-right" "$G1"
BETA=$WID

open_thunar -w -g +20+30 "$WORK/gamma"
wait_title "$WID" gamma
sleep 1
geom "$WID"
near "$FX" 18 22 "thunar -g +20+30: the frame's x"
near "$FY" 28 32 "thunar -g +20+30: the frame's y"

open_thunar -g 500x400+60+60 -t "$WORK/alpha" -T "$WORK/beta"
wait_title "$WID" alpha
sleep 1
geom "$WID"
(( GW >= 500 && GH >= 400 )) || fail "thunar -g 500x400 -t alpha -T beta opened a ${GW}x${GH} window"

sleep 2
[[ $(remembered) == "$WIDTH_BEFORE" ]] || fail "/last-window-width changed from $WIDTH_BEFORE to $(remembered) after --geometry"

sleep 3
xdotool windowsize --sync "$BETA" 700 450
sleep 2
[[ $(remembered) == 700 ]] || fail "after resizing beta by hand to 700 wide, /last-window-width is $(remembered)"

open_thunar -w -g 12x "$WORK/delta" 2> "$WORK/err.txt"
wait_title "$WID" delta
grep -qF 'Thunar: invalid geometry "12x"' "$WORK/err.txt" || fail "thunar -g 12x printed '$(cat "$WORK/err.txt")'"

DESKTOPS=$(xdotool get_num_desktops)
(( DESKTOPS >= 2 )) || { xdotool set_num_desktops 2; sleep 1; }
xdotool set_desktop 0
sleep 1

thunar -w -s 2 -g 800x500+100+100 "$WORK/epsilon" &
find_window epsilon
sleep 2
[[ $(xdotool get_desktop_for_window "$WID") == 1 ]] || fail "thunar -s 2 put the window on workspace index $(xdotool get_desktop_for_window "$WID"), expected 1"
[[ $(xdotool get_desktop) == 0 ]] || fail "thunar -s 2 switched to workspace index $(xdotool get_desktop)"
shot root before-workspace "After thunar -s 2 -g 800x500+100+100 epsilon the user is still on workspace 1, which still shows the earlier Thunar windows and none titled epsilon"
xdotool set_desktop 1
sleep 1
geom "$WID"
(( GW == 800 && GH == 500 )) || fail "thunar -s 2 -g 800x500+100+100 opened a ${GW}x${GH} window"
shot root after-workspace "Switching to workspace 2 shows the epsilon window there, 800x500 at (100, 100)"
pair workspace "Ran thunar -s 2 -g 800x500+100+100 epsilon on workspace 1, then switched to workspace 2" "The window opens on workspace 2 at its geometry and the user stays on workspace 1" "workspace 1: no epsilon window" "workspace 2: epsilon 800x500 at (100, 100)" "$G2"
xdotool set_desktop 0
sleep 1

open_thunar -w -s 9 "$WORK/zeta" 2> "$WORK/err.txt"
wait_title "$WID" zeta
grep -qF 'Thunar: invalid workspace "9"' "$WORK/err.txt" || fail "thunar -s 9 printed '$(cat "$WORK/err.txt")'"
[[ $(xdotool get_desktop_for_window "$WID") == 0 ]] || fail "thunar -s 9 didn't open the window on the current workspace"

help=$(thunar --help)
grep -q -- '-g, --geometry=GEOMETRY' <<<"$help" || fail "thunar --help doesn't list -g, --geometry=GEOMETRY"
grep -q -- '-s, --workspace=N' <<<"$help" || fail "thunar --help doesn't list -s, --workspace=N"
