#!/bin/bash
# Issue #135: Enter in the search bar moves the focus to the file list, so Down selects the first match.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
DIR="$WORK/files"

mkdir -p "$DIR"
for f in apple1.txt apple2.txt banana.txt; do
  echo "$f" > "$DIR/$f"
done

go() {  # path
  focus "$WID"
  xdotool key ctrl+l
  sleep 0.3
  xdotool type --delay 5 "$1"
  xdotool key Return
  wait_title "$WID" "$(basename "$1")"
  xdotool key Escape
  sleep 0.5
}

search() {  # query
  focus "$WID"
  xdotool key ctrl+f
  sleep 0.5
  xdotool type --delay 20 "$1"
  sleep 2
}

pasted_is() {  # check name, the files the clipboard must hold
  local dest="$WORK/check-$1" got want i
  shift
  mkdir -p "$dest"
  focus "$WID"
  xdotool key Escape
  sleep 1
  go "$dest"
  xdotool key ctrl+v
  want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | sort | tr '\n' ' ')
    [[ $got == "$want" ]] && return 0
    sleep 0.2
  done
  fail "the clipboard held '$got', expected '$want'"
}

copy_all() {
  focus "$WID"
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 100)) click 1
  sleep 0.5
  xdotool key ctrl+a ctrl+c
  sleep 0.5
}

open_thunar "$DIR"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" files
focus "$WID"
xdotool key ctrl+2
sleep 0.5

search apple
shot "$WID" before-enter "Searching files for apple lists apple1.txt and apple2.txt, with the focus in the search box and no file selected"
focus "$WID"
xdotool key Return
sleep 0.5
xdotool key Down
sleep 0.5
shot "$WID" after-enter "After Enter, Down in the search box, apple1.txt, the first match, is selected in the result list and the search still shows both matches"
pair enter "Pressed Enter, then Down, in the search box" "Enter moves the focus to the results, so Down selects the first match and the search stays" "Search for apple, focus in the search box" "Enter, Down: apple1.txt selected" "Enter in the search bar"
focus "$WID"
xdotool key ctrl+c
sleep 0.5
pasted_is first apple1.txt

go "$DIR"
search apple
focus "$WID"
xdotool key Return
sleep 0.5
xdotool key ctrl+a ctrl+c
sleep 0.5
pasted_is results apple1.txt apple2.txt

xfconf-query -c thunar -p /last-location-bar -n -t string -s ThunarLocationButtons
sleep 1
go "$DIR"
focus "$WID"
xdotool key ctrl+l
sleep 0.5
search apple
focus "$WID"
xdotool key Return
sleep 1
shot "$WID" buttons-bar "With the path-buttons location bar, after Ctrl+L, Ctrl+F, apple and Enter, the search box still shows Search: apple above the two apple results"
focus "$WID"
xdotool key ctrl+a ctrl+c
sleep 0.5
pasted_is buttons apple1.txt apple2.txt

go "$DIR"
search zzz
focus "$WID"
xdotool key Return Down
sleep 1
kill -0 "$THUNAR_PID" || fail "Thunar exited after Enter on a search with no matches"

go "$DIR"
copy_all
focus "$WID"
xdotool key ctrl+l
sleep 0.5
xdotool key ctrl+a
xdotool type --delay 20 "Search: apple"
sleep 2
xdotool key Return
sleep 0.5
xdotool key ctrl+a ctrl+c
sleep 0.5
pasted_is typed apple1.txt apple2.txt

xfconf-query -c thunar -p /last-location-bar -n -t string -s ThunarLocationEntry
sleep 1
go "$DIR"
copy_all
focus "$WID"
xdotool key ctrl+l
sleep 0.5
xdotool key ctrl+a
xdotool type --delay 20 "Search: apple"
sleep 2
xdotool key Return
sleep 0.5
xdotool key ctrl+a ctrl+c
sleep 0.5
pasted_is typed-entry apple1.txt apple2.txt
