#!/bin/bash
# Issue #93: Enter on a file's path in the location bar opens the file's folder and selects the file, instead of launching it.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700

mkdir -p "$WORK/start" "$WORK/sub" "$WORK/many"
for f in alpha.txt beta.txt gamma.txt target.txt zulu.txt; do echo "$f" > "$WORK/sub/$f"; done
for i in $(seq -w 1 60); do echo "$i" > "$WORK/many/file-$i.txt"; done
printf '#!/bin/sh\ntouch "%s/ran"\n' "$WORK" > "$WORK/sub/run-me.sh"
chmod +x "$WORK/sub/run-me.sh"

xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView

F='Enter on a file path selects the file'
O='Folder paths and scripts'

N=0
selected_is() {  # expected name
  local dest got i
  N=$((N + 1))
  dest="$WORK/check-$N"
  mkdir -p "$dest"
  focus "$MAIN"
  xdotool key ctrl+c
  sleep 0.3
  open_thunar "$dest"
  wait_title "$WID" "check-$N"
  focus "$WID"
  xdotool key ctrl+v
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | tr '\n' ' ')
    [[ $got == "$1 " ]] && break
    sleep 0.2
  done
  xdotool key ctrl+w
  sleep 0.5
  WID=$MAIN
  [[ $got == "$1 " ]] || fail "check $N: the selection held '$got', expected '$1'"
}

type_path() {  # path
  focus "$MAIN"
  xdotool key ctrl+l
  sleep 0.3
  xdotool type --delay 5 "$1"
  sleep 0.5
}

others() {  # windows other than the main one
  xdotool search --all --onlyvisible --name . 2>/dev/null | grep -vx "$MAIN" | while read -r w; do
    xdotool getwindowname "$w" 2>/dev/null || true
  done | grep -v '^$' || true
}

open_thunar "$WORK/start"
MAIN=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" start
sleep 1
BEFORE_OTHERS=$(others)

# A file in a small folder
type_path "$WORK/sub/target.txt"
shot "$MAIN" before-file "Thunar on the empty folder start, with the path to sub/target.txt typed in the location bar"
xdotool key Return
wait_title "$MAIN" sub
sleep 1.5
shot "$MAIN" after-file "Thunar now shows folder sub with target.txt selected (status bar: \"target.txt\" selected), and no editor opened"
pair file "Typed the path to sub/target.txt in the location bar and pressed Enter" "Enter on a file path opens its folder and selects the file instead of launching it" "on start, path to target.txt typed" "on sub, target.txt selected" "$F"
[[ $(others) == "$BEFORE_OTHERS" ]] || fail "a new window opened after Enter on target.txt: $(others)"
selected_is target.txt

# A file far down a long folder is scrolled into view
type_path "$WORK/many/file-55.txt"
xdotool key Return
wait_title "$MAIN" many
sleep 1.5
shot "$MAIN" scrolled-into-view "Folder many in details view, scrolled down so that the selected file-55.txt row is in view"
selected_is file-55.txt

# A folder path still opens the folder
type_path "$WORK/sub"
xdotool key Return
wait_title "$MAIN" sub
sleep 0.5

# An executable script is selected, not run
type_path "$WORK/sub/run-me.sh"
shot "$MAIN" before-script "Thunar on folder sub with the path to the executable sub/run-me.sh typed in the location bar"
xdotool key Return
sleep 2
[[ $(xdotool getwindowname "$MAIN") == *sub* ]] || fail "the title went to '$(xdotool getwindowname "$MAIN")'"
[[ ! -e $WORK/ran ]] || fail "Enter on run-me.sh ran the script"
[[ $(others) == "$BEFORE_OTHERS" ]] || fail "a new window opened after Enter on run-me.sh: $(others)"
shot "$MAIN" after-script "Still on folder sub, with run-me.sh selected and no dialog asking to run it; the script did not run"
pair script "Typed the path to the executable sub/run-me.sh and pressed Enter, then waited 2 s" "Enter on an executable selects it and never runs it or asks to" "on sub, path to run-me.sh typed" "run-me.sh selected, not run" "$O"
selected_is run-me.sh

# The buttons bar's temporary entry (Ctrl+L) selects the file too
xfconf-query -c thunar -p /last-location-bar -n -t string -s ThunarLocationButtons
open_thunar "$WORK/sub"
MAIN=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" sub
sleep 1
type_path "$WORK/many/file-07.txt"
shot "$MAIN" before-buttons "Location bar in buttons style, on folder sub, with the path to many/file-07.txt typed in the temporary entry Ctrl+L opened"
xdotool key Return
wait_title "$MAIN" many
sleep 1.5
shot "$MAIN" after-buttons "The buttons bar now ends in many, and file-07.txt is selected in folder many"
pair buttons "In buttons style, pressed Ctrl+L, typed the path to many/file-07.txt and pressed Enter" "The buttons bar's temporary entry also opens the folder and selects the file" "buttons bar, path to file-07.txt typed" "on many, file-07.txt selected" "$F"
selected_is file-07.txt
