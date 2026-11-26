#!/bin/bash
# Issue #143: while a name is edited in place, Tab saves it and edits the next row's name, Shift+Tab the previous row's.
set -euo pipefail
. .github/scripts/verify-lib.sh

ROW0=$((103 + (EUID == 0 ? 34 : 0)))
NAME_X=230
DIR="$WORK/files"

mkdir -p "$DIR"
for f in a b c d; do echo "$f" > "$DIR/$f.txt"; done
xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView

G='Tab and Shift+Tab in the name entry'

exists() {
  local i
  for ((i = 0; i < 25; i++)); do
    [[ -e $1 ]] && return 0
    sleep 0.2
  done
  fail "$2: $(basename "$1") does not exist; the folder holds: $(ls "$DIR" | tr '\n' ' ')"
}

holds() {
  local want="$1" got i
  for ((i = 0; i < 25; i++)); do
    got=$(ls "$DIR" | tr '\n' ' ')
    [[ $got == "$want" ]] && return 0
    sleep 0.2
  done
  fail "$2: the folder holds '$got', expected '$want'"
}

keys() {
  focus "$MAIN"
  xdotool key "$@"
  sleep 0.5
}

click_first_row() {
  focus "$MAIN"
  xdotool mousemove --window "$MAIN" "$NAME_X" "$ROW0"
  sleep 0.3
  xdotool click 1
  sleep 0.5
  xdotool mousemove --window "$MAIN" 500 560
}

f2() {
  keys F2
  sleep 0.5
}

open_thunar "$DIR"
MAIN=$WID
xdotool windowsize --sync "$MAIN" 1000 600
xdotool windowmove --sync "$MAIN" 0 0
wait_title "$MAIN" files

click_first_row
f2
shot "$MAIN" before-tab "a.txt, the first of a b c d, has its Name cell turned into an entry with 'a' selected"
xdotool type --delay 20 one
xdotool key Tab
sleep 1
exists "$DIR/one.txt" "typing one over 'a' and pressing Tab"
shot "$MAIN" after-tab "Tab saved a.txt as one.txt and turned b.txt's Name cell into an entry with 'b' selected and b.txt's row selected"
pair tab "Pressed F2 on a.txt, typed one, pressed Tab" "Tab saves the name and edits the next file's name" "entry on a.txt" "one.txt saved, entry on b.txt" "$G"
xdotool type --delay 20 two
xdotool key Tab
sleep 1
exists "$DIR/two.txt" "typing two over 'b' and pressing Tab"
xdotool key Tab
sleep 1
xdotool key Escape
sleep 0.5
holds "c.txt d.txt one.txt two.txt " "Tab on a, b and the unchanged c, then Escape on d"

click_first_row
keys Down
f2
xdotool type --delay 20 four
shot "$MAIN" before-shift-tab "d.txt, the second row, has its Name cell in an entry with 'four' typed over 'd'"
xdotool key shift+Tab
sleep 1
exists "$DIR/four.txt" "typing four over 'd' and pressing Shift+Tab"
shot "$MAIN" after-shift-tab "Shift+Tab saved d.txt as four.txt and turned c.txt's Name cell, the row above, into an entry with 'c' selected"
pair shift-tab "Pressed F2 on d.txt, typed four, pressed Shift+Tab" "Shift+Tab saves the name and edits the previous file's name" "'four' typed on d.txt" "four.txt saved, entry on c.txt" "$G"
xdotool key Escape
sleep 0.5
holds "c.txt four.txt one.txt two.txt " "Shift+Tab from d to c, then Escape on c"

click_first_row
keys End
f2
xdotool type --delay 20 last
xdotool key Tab
sleep 1
exists "$DIR/last.txt" "typing last over 'two' on the last row and pressing Tab"
shot "$MAIN" last-row "Tab on two.txt, the last row, saved it as last.txt and left no entry open in any row"
holds "c.txt four.txt last.txt one.txt " "Tab on the last row"

click_first_row
f2
xdotool key ctrl+a
xdotool type --delay 20 'a/b'
xdotool key Tab
sleep 1
shot "$MAIN" invalid-tab "Tab with 'a/b' typed left the entry open in c.txt's row, the first, with its error icon"
holds "c.txt four.txt last.txt one.txt " "Tab with the invalid name a/b"
xdotool key BackSpace BackSpace Tab
sleep 1
exists "$DIR/a" "deleting /b from the a/b still in the entry and pressing Tab"
xdotool key Escape
sleep 0.5
holds "a four.txt last.txt one.txt " "Tab after fixing a/b to a, then Escape on four.txt"
