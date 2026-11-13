#!/bin/bash
# Issue #118: with Expandable Folders on, Ctrl+Shift+A selects everything inside the folder at the cursor.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
ROW0=$((103 + (EUID == 0 ? 34 : 0)))
ROW_H=${ROW_H:-26}
NAME_X=239
DIR="$WORK/files"

mkdir -p "$DIR/a/sub" "$DIR/b"
echo a1 > "$DIR/a/a1.txt"
echo a2 > "$DIR/a/a2.txt"
echo s1 > "$DIR/a/sub/s1.txt"
echo b1 > "$DIR/b/b1.txt"
echo top > "$DIR/top.txt"

xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView
xfconf-query -c thunar -p /misc-expandable-folders -n -t bool -s true

click_row() {
  focus "$MAIN"
  xdotool mousemove --window "$MAIN" "$NAME_X" $((ROW0 + $1 * ROW_H))
  sleep 0.3
  xdotool click 1
  sleep 0.3
}

keys() {
  focus "$MAIN"
  local k
  for k in "$@"; do
    xdotool key "$k"
    sleep 0.2
  done
  sleep 0.3
}

N=0
selected_is() {
  local dest got want i
  N=$((N + 1))
  dest="$WORK/check-$N"
  mkdir -p "$dest"
  keys ctrl+c
  open_thunar "$dest"
  wait_title "$WID" "check-$N"
  focus "$WID"
  xdotool key ctrl+v
  want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | sort | tr '\n' ' ')
    [[ $got == "$want" ]] && break
    sleep 0.2
  done
  xdotool key ctrl+w
  sleep 0.5
  WID=$MAIN
  [[ $got == "$want" ]] || fail "check $N: the selection held '$got', expected '$want'"
}

G='Ctrl+Shift+A in expanded folders'

open_thunar "$DIR"
MAIN=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" files
sleep 1

click_row 0
keys Right
sleep 1
click_row 1
keys Right
sleep 1
click_row 5
keys Right
sleep 1

click_row 3
selected_is a1.txt
shot "$MAIN" before-inside-a "a, a/sub and b are expanded; the cursor is on a1.txt inside a, and only a1.txt is selected"
keys ctrl+shift+a
selected_is a1.txt a2.txt sub s1.txt
shot "$MAIN" after-inside-a "Ctrl+Shift+A on a1.txt selected sub, s1.txt, a1.txt and a2.txt (4 items), but not a, b, b1.txt or top.txt"
pair inside-a "Put the cursor on a1.txt inside the expanded folder a, then pressed Ctrl+Shift+A" "Ctrl+Shift+A selects every row in the cursor's parent folder, at all depths, and nothing outside it" "a1.txt selected" "sub, s1.txt, a1.txt, a2.txt selected" "$G"

keys ctrl+space
selected_is a2.txt sub s1.txt
shot "$MAIN" cursor-stays "Ctrl+Space after Ctrl+Shift+A unselected a1.txt only, so the cursor stayed on a1.txt"

click_row 0
keys ctrl+shift+a
selected_is a1.txt a2.txt sub s1.txt
shot "$MAIN" on-expanded-folder "Ctrl+Shift+A with the cursor on the expanded folder a selected its 4 rows but not the a row itself"

click_row 2
keys ctrl+shift+a
selected_is s1.txt
shot "$MAIN" nested-folder "Ctrl+Shift+A on s1.txt inside a/sub selected only s1.txt, the one row in its parent folder sub"

click_row 4
selected_is a2.txt
keys alt+e f
selected_is a1.txt a2.txt sub s1.txt
shot "$MAIN" edit-menu "Edit > Select All in Folder with the cursor on a2.txt selected the same 4 rows inside a as Ctrl+Shift+A"

click_row 0
keys End
selected_is top.txt
keys ctrl+shift+a
selected_is a sub s1.txt a1.txt a2.txt b b1.txt top.txt
shot "$MAIN" top-level-all "Ctrl+Shift+A on the top-level file top.txt selected every row in the view, like Ctrl+A"

xfconf-query -c thunar -p /misc-expandable-folders -s false
sleep 1
click_row 0
keys End
selected_is top.txt
keys ctrl+shift+a
selected_is a b top.txt
shot "$MAIN" expandable-off "With Expandable Folders off, Ctrl+Shift+A on top.txt selected all three rows, like Ctrl+A"
