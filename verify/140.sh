#!/bin/bash
# Issue #140: in split view, a shortcut bound to Switch Focused Split View Pane (here F6) switches the active pane and
# the keyboard focus. Outside split view the shortcut leaves F6 to GTK, which moves the focus to the side pane.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
G='Switch Focused Split View Pane shortcut (#140)'

mkdir -p "$WORK/leftdir/sub" "$WORK/rightdir" "${XDG_CONFIG_HOME:-$HOME/.config}/Thunar"
echo 1 > "$WORK/rightdir/b1.txt"
echo 2 > "$WORK/rightdir/b2.txt"
printf '(gtk_accel_path "<Actions>/ThunarWindow/switch-focused-split-view-pane" "F6")\n' \
  > "${XDG_CONFIG_HOME:-$HOME/.config}/Thunar/accels.scm"

title() { xdotool getwindowname "$WID"; }

starts() { [[ $(title) == "$1" || $(title) == "$1 "* ]]; }

wait_start() {  # name
  local i
  for ((i = 0; i < 50; i++)); do
    starts "$1" && return 0
    sleep 0.2
  done
  fail "window title is '$(title)', expected it to start with '$1'"
}

wait_file() {  # path present|absent
  local i
  for ((i = 0; i < 50; i++)); do
    if [[ $2 == present ]]; then [[ -e $1 ]] && return 0; else [[ ! -e $1 ]] && return 0; fi
    sleep 0.2
  done
  fail "expected $1 to be $2"
}

park() { xdotool mousemove --window "$WID" $((W / 2)) 5; }

click_at() {  # x y
  xdotool mousemove --window "$WID" "$1" "$2"
  sleep 0.2
  xdotool click 1
  park
}

goto() {  # x-in-pane folder
  click_at "$1" $((H - 80))
  sleep 0.3
  xdotool key ctrl+l
  sleep 0.3
  xdotool type --delay 5 "$WORK/$2"
  xdotool key Return
  wait_start "$2"
  xdotool key Escape
  sleep 0.3
}

open_thunar "$WORK/leftdir"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_start leftdir
focus "$WID"
xdotool key ctrl+2
sleep 0.5

# Split view off: F6 goes on to GTK, which moves the focus from the file list to the side pane.
# Down and Return then open a side pane place; with the focus still in the file list they would open sub.
click_at $((W * 3 / 4)) $((H - 80))
sleep 0.5
xdotool key F6
sleep 1
xdotool key Down
sleep 0.5
xdotool key Return
for ((i = 0; i < 50; i++)); do
  starts leftdir || break
  sleep 0.2
done
sleep 0.5
if starts leftdir || starts sub; then
  fail "with split view off, F6 then Down and Return left the window at '$(title)': F6 did not move the focus to the side pane"
fi
shot "$WID" split-off "Split view off: F6 moved the focus to the side pane, so Down and Return opened $(title | sed 's/ - Thunar$//') from it, not sub from leftdir (the script asserts the title)"
xdotool key alt+Left
wait_start leftdir

xdotool key F9
sleep 0.5
xdotool key F3
sleep 1
goto $((W * 3 / 4)) rightdir

click_at $((W / 4)) $((H - 80))
wait_start leftdir
sleep 0.5
shot "$WID" before-f6 "Split view with leftdir (folder sub) on the left and rightdir (b1.txt, b2.txt) on the right; the left pane is active and the title is leftdir"
xdotool key F6
sleep 1
starts rightdir || fail "F6 bound to Switch Focused Split View Pane left the active pane at '$(title)', expected rightdir"
shot "$WID" after-f6 "After F6 the right pane (rightdir) is active and the title is rightdir (the script asserts the title)"
pair f6 "Bound F6 to Switch Focused Split View Pane, clicked the left pane, then pressed F6" "The shortcut moves the active pane from left to right" "left pane active, title leftdir" "right pane active, title rightdir" "$G"

xdotool key F6
sleep 1
starts leftdir || fail "a second F6 left the active pane at '$(title)', expected leftdir"
shot "$WID" f6-again "A second F6 switches back: the left pane (leftdir) is active again and the title is leftdir (the script asserts the title)"

# The keyboard focus moves too: End and F2 after F6 rename the right pane's last file.
xdotool key F6
sleep 1
starts rightdir || fail "a third F6 left the active pane at '$(title)', expected rightdir"
xdotool key End
sleep 0.5
xdotool key F2
sleep 1
xdotool key ctrl+a
xdotool type --delay 5 renamed
xdotool key Return
wait_file "$WORK/rightdir/renamed" present
wait_file "$WORK/rightdir/b2.txt" absent
[[ -e $WORK/rightdir/b1.txt && -d $WORK/leftdir/sub ]] || fail "End and F2 after F6 renamed the wrong item"
sleep 1
shot "$WID" focus-right "After F6, End and F2 renamed b2.txt in the right pane to renamed, so the keyboard focus is in the right pane's file list (the script asserts the files)"
