#!/bin/bash
# Issue #96: in split view, a drop from one pane on the other, and Insert (#95), leave keyboard focus and the
# active pane on the source pane; New Folder still focuses the new folder in its own pane.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
G='Focus after a drop between panes (#96)'

mkdir -p "$WORK/left" "$WORK/right"
echo a > "$WORK/right/a.txt"

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

open_thunar "$WORK/left"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_start left
focus "$WID"
xdotool key ctrl+2
sleep 0.5
xdotool key F9
sleep 0.5
xdotool key F3
sleep 1
goto $((W * 3 / 4)) right

# Drag a.txt, the only file in right, from its row and drop it on the left pane's empty area.
# Try around the first row's position, as verify/15.sh finds it.
ROW0=$((103 + (EUID == 0 ? 34 : 0)))
SX=$((W / 2 + 50))
dropped=''
for ry in $ROW0 $((ROW0 + 8)) $((ROW0 - 8)) $((ROW0 + 16)) $((ROW0 + 24)) $((ROW0 - 16)) $((ROW0 + 32)) $((ROW0 + 40)); do
  focus "$WID"
  xdotool mousemove --window "$WID" "$SX" "$ry"
  sleep 0.3
  xdotool mousedown 1
  for ((s = 1; s <= 10; s++)); do
    xdotool mousemove --window "$WID" $((SX + (W / 4 - SX) * s / 10)) $((ry + (H / 2 + 100 - ry) * s / 10))
    sleep 0.08
  done
  sleep 0.3
  xdotool mouseup 1
  park
  sleep 1.5
  if [[ -e $WORK/left/a.txt ]]; then dropped=$ry; break; fi
  wait_start right
done
[[ -n $dropped ]] || fail "dragging from the right pane to the left pane never moved a.txt into left"
echo "a.txt row y=$dropped"
wait_file "$WORK/right/a.txt" absent
starts right || fail "after the drop the active pane is '$(title)', expected right"

echo b > "$WORK/right/b.txt"
echo c > "$WORK/right/c.txt"
sleep 1.5
shot "$WID" before-drop-down "After dropping a.txt from right on left: left shows a.txt, the right pane (now b.txt and c.txt) is still active"
xdotool key Down
sleep 1
starts right || fail "Down after the drop switched the window to '$(title)': focus was in the drop pane"
shot "$WID" after-drop-down "After Down the right pane is still the active pane (the script asserts the title)"
pair drop-down "Dragged a.txt from the right pane onto the left pane, then pressed Down" "After a drop between panes, the pane the drag started from stays active" "a.txt dropped on left, right active" "right still active after Down" "$G"

# The next keys act on the right pane: Ctrl+A then Insert move right's files, not left's a.txt
xdotool key ctrl+a
sleep 0.5
shot "$WID" before-insert-down "Ctrl+A after the drop selected b.txt and c.txt in the right pane, which is still active"
xdotool key Insert
wait_file "$WORK/left/b.txt" present
wait_file "$WORK/left/c.txt" present
[[ -e $WORK/left/a.txt && ! -e $WORK/right/a.txt ]] || fail "Ctrl+A and Insert acted on the left pane: a.txt moved back to right"
sleep 1
xdotool key Down
sleep 1
starts right || fail "Down after Insert switched the window to '$(title)': focus was in the target pane"
shot "$WID" after-insert-down "Insert moved b.txt and c.txt to left, and after Down the right pane (now empty) is still active (the script asserts both)"
pair insert-down "Pressed Ctrl+A and Insert in the right pane, then Down" "Ctrl+A acted on the drag's source pane, and Insert also leaves focus there" "b.txt, c.txt selected in right" "both in left, right still active" "$G"

# New Folder still focuses the new folder: F2 right after it renames that folder
click_at $((W / 4)) $((H - 80))
wait_start left
xdotool key ctrl+shift+n
sleep 1
xdotool key ctrl+a
xdotool type --delay 5 made
xdotool key Return
wait_file "$WORK/left/made" present
sleep 1
xdotool key F2
sleep 1
xdotool key ctrl+a
xdotool type --delay 5 renamed
xdotool key Return
wait_file "$WORK/left/renamed" present
wait_file "$WORK/left/made" absent
sleep 1
starts left || fail "after New Folder and rename the active pane is '$(title)', expected left"
shot "$WID" new-folder "In the left pane, Ctrl+Shift+N made folder made and F2 then renamed it to renamed, so New Folder still focuses the new folder (the script asserts both names)"
