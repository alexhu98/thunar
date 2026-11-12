#!/bin/bash
# Issue #95: in split view, Insert drops the selection on the other pane, moving or copying it as a drop would;
# in the location bar Insert stays a text key, and without split view it does nothing.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
G='Insert in split view (#95)'

mkdir -p "$WORK/left" "$WORK/right" "$WORK/other" "$WORK/zz"
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

select_right() {
  click_at $((W * 3 / 4)) $((H - 80))
  wait_start right
  xdotool key ctrl+a
  sleep 0.5
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

# Insert: same filesystem and a writable source folder, so it moves, as a drop does
select_right
shot "$WID" before-insert "Split view: the left pane shows left (empty), the right pane is active on right with a.txt selected"
xdotool key Insert
wait_file "$WORK/left/a.txt" present
wait_file "$WORK/right/a.txt" absent
sleep 1
starts right || fail "after Insert the active pane is '$(title)', expected focus to stay on right"
shot "$WID" after-insert "a.txt is now in the left pane and gone from the right pane, which stays active (the script asserts both folders)"
pair insert "Selected a.txt in the right pane and pressed Insert" "Insert drops the selection on the other pane: same filesystem, so it moves" "right has a.txt, left empty" "left has a.txt, right empty" "$G"

# In the location bar Insert is a text key: it moves no file
echo b > "$WORK/right/b.txt"
sleep 1.5
select_right
xdotool key F9
sleep 0.5
click_at 60 $((H - 80))
sleep 0.3
starts right || fail "clicking the side pane changed the window to '$(title)'"
shot "$WID" before-side-pane "The side pane is shown and focused by a click on its empty area, while b.txt is selected in the active right pane"
xdotool key Insert
sleep 1.5
[[ -e $WORK/right/b.txt && ! -e $WORK/left/b.txt ]] || fail "Insert with focus in the side pane transferred b.txt"
shot "$WID" after-side-pane "1.5 s after Insert with focus in the side pane, b.txt is still in right and not in left (the script asserts it)"
pair side-pane "Selected b.txt in the right pane, clicked the side pane's empty area and pressed Insert" "Insert acts only when focus is in the file view" "side pane focused, b.txt in right" "b.txt still in right, left empty" "$G"
xdotool key F9
sleep 0.5
select_right
xdotool key ctrl+l
sleep 0.3
xdotool key ctrl+a
xdotool type --delay 5 "$WORK/zz"
sleep 0.5
shot "$WID" before-entry "The right pane's location bar holds the path of zz while b.txt is selected in right"
xdotool key Insert
sleep 1.5
[[ -e $WORK/right/b.txt && ! -e $WORK/left/b.txt ]] || fail "Insert in the location bar transferred b.txt"
xdotool key Insert Return
wait_start zz
shot "$WID" after-entry "Insert in the location bar moved nothing; Return then opened zz in the right pane (the script asserts b.txt stayed in right)"
pair entry "Typed the path of zz in the right pane's location bar, pressed Insert twice and Return" "In a text field Insert stays a text key and moves no file" "location bar holds zz, b.txt in right" "right pane on zz, b.txt still in right" "$G"

# Without split view Insert does nothing
xdotool key Escape
sleep 0.3
xdotool key F3
sleep 1
goto $((W / 2)) right
click_at $((W / 2)) $((H - 80))
xdotool key ctrl+a
sleep 0.5
shot "$WID" before-no-split "Split view off: the window shows right with b.txt selected"
xdotool key Insert
sleep 2
[[ -e $WORK/right/b.txt && ! -e $WORK/left/b.txt && ! -e $WORK/zz/b.txt ]] || fail "Insert without split view transferred b.txt"
starts right || fail "Insert without split view changed the window to '$(title)'"
shot "$WID" after-no-split "2 s after Insert, b.txt is still in right and in no other folder (the script asserts it)"
pair no-split "With split view off, selected b.txt and pressed Insert" "Without split view Insert does nothing" "split view off, b.txt selected" "b.txt still only in right" "$G"
