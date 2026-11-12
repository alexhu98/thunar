#!/bin/bash
# Issue #95: in split view, Insert drops the selection on the other pane, Shift+Insert copies it there and
# Ctrl+Insert moves it there; in the location bar Shift+Insert and Ctrl+Insert still paste and copy text.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
G='Insert keys in split view (#95)'

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

# Shift+Insert: always copies
echo b > "$WORK/right/b.txt"
sleep 1.5
select_right
shot "$WID" before-shift-insert "The right pane is active on right with b.txt selected; the left pane shows left with a.txt"
xdotool key shift+Insert
wait_file "$WORK/left/b.txt" present
sleep 1
[[ -e $WORK/right/b.txt ]] || fail "Shift+Insert moved b.txt instead of copying it"
starts right || fail "after Shift+Insert the active pane is '$(title)', expected focus to stay on right"
shot "$WID" after-shift-insert "b.txt is in both panes: Shift+Insert copied it (the script asserts both folders have it)"
pair shift-insert "Selected b.txt in the right pane and pressed Shift+Insert" "Shift+Insert copies the selection to the other pane's folder" "b.txt only in right" "b.txt in left and in right" "$G"

# Ctrl+Insert: always moves, here onto a pane showing another folder
goto $((W / 4)) other
select_right
shot "$WID" before-ctrl-insert "The left pane now shows other (empty); the right pane is active on right with b.txt selected"
xdotool key ctrl+Insert
wait_file "$WORK/other/b.txt" present
wait_file "$WORK/right/b.txt" absent
sleep 1
starts right || fail "after Ctrl+Insert the active pane is '$(title)', expected focus to stay on right"
shot "$WID" after-ctrl-insert "b.txt moved into other, the left pane's folder, and is gone from right (the script asserts both folders)"
pair ctrl-insert "Selected b.txt in the right pane and pressed Ctrl+Insert" "Ctrl+Insert moves the selection to the other pane's folder" "b.txt in right, other empty" "b.txt in other, right empty" "$G"

# In the location bar, Ctrl+Insert copies text and Shift+Insert pastes it; no file moves
echo c > "$WORK/right/c.txt"
sleep 1.5
select_right
xdotool key ctrl+l
sleep 0.3
xdotool key ctrl+a
xdotool type --delay 5 "zz"
xdotool key shift+Home ctrl+Insert BackSpace
xdotool type --delay 5 "$WORK/"
sleep 0.5
shot "$WID" before-entry-paste "The right pane's location bar holds $WORK/ after Ctrl+Insert copied zz from it; c.txt is in right"
xdotool key shift+Insert
sleep 0.5
shot "$WID" after-entry-paste "Shift+Insert pasted zz into the location bar, giving $WORK/zz; c.txt is still in right"
xdotool key Return
wait_start zz
[[ -e $WORK/right/c.txt ]] || fail "Ctrl+Insert or Shift+Insert in the location bar moved c.txt"
[[ ! -e $WORK/other/c.txt ]] || fail "Ctrl+Insert or Shift+Insert in the location bar transferred c.txt to other"
pair entry-paste "In the location bar, copied zz with Ctrl+Insert, typed $WORK/ and pressed Shift+Insert" "In a text field the keys still copy and paste text and move no file" "location bar: the work folder/" "location bar: the work folder/zz" "$G"

# With split view off the actions let the keys through, so Ctrl+Insert and Shift+Insert still copy and paste files
xdotool key Escape
sleep 0.3
xdotool key F3
sleep 1
goto $((W / 2)) right
click_at $((W / 2)) $((H - 80))
xdotool key ctrl+a
sleep 0.5
xdotool key ctrl+Insert
sleep 0.5
goto $((W / 2)) zz
click_at $((W / 2)) $((H - 80))
shot "$WID" before-no-split "Split view off: the window shows zz (empty) after Ctrl+Insert copied c.txt from right to the clipboard"
xdotool key shift+Insert
wait_file "$WORK/zz/c.txt" present
sleep 1
[[ -e $WORK/right/c.txt ]] || fail "Ctrl+Insert then Shift+Insert with split view off moved c.txt instead of copying it"
shot "$WID" after-no-split "Shift+Insert pasted c.txt into zz; right still has it (the script asserts both folders)"
pair no-split "With split view off, pressed Ctrl+Insert on c.txt in right, opened zz and pressed Shift+Insert" "Without split view the keys keep their clipboard copy and paste" "zz empty, c.txt copied" "zz has c.txt, right still has it" "$G"
