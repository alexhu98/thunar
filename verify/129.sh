#!/bin/bash
# Issue #129: the details view applies file changes in the folder it shows (a size change re-sorts the row, a hidden
# temp file renamed to a visible name appears), with Expandable Folders off and on, and logs no "detached node".
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=600
DEST_DIR="$WORK/dest"
TLOG="$WORK/thunar.log"

mkdir -p "$DEST_DIR"
: > "$TLOG"
trap 'status=$?; (( status == 0 )) || { echo "Thunar log:" >&2; tail -n 20 "$TLOG" >&2; }' EXIT

xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView
xfconf-query -c thunar -p /last-sort-column -n -t string -s THUNAR_COLUMN_SIZE
xfconf-query -c thunar -p /last-sort-order -n -t string -s GTK_SORT_ASCENDING
xfconf-query -c thunar -p /misc-expandable-folders -n -t bool -s false

paste_names() {
  local want=$1 got='' i
  focus "$CUR"
  xdotool key ctrl+c
  sleep 0.2
  focus "$DEST"
  xdotool key ctrl+v
  for ((i = 0; i < 30; i++)); do
    got=$(ls -A "$DEST_DIR" | tr '\n' ' ')
    [[ $got == "$want " ]] && break
    sleep 0.1
  done
  sleep 0.2
  rm -f "$DEST_DIR"/*
  focus "$CUR"
  NAMES=$got
}

first_row_is() {
  local want=$1 i
  for ((i = 0; i < 8; i++)); do
    focus "$CUR"
    xdotool key Home
    sleep 0.3
    paste_names "$want"
    [[ $NAMES == "$want " ]] && return 0
    sleep 0.5
  done
  fail "$2: the first row is '$NAMES', expected '$want'"
}

listed_are() {
  local want=$1 i
  for ((i = 0; i < 8; i++)); do
    focus "$CUR"
    xdotool key ctrl+a
    sleep 0.3
    paste_names "$want"
    [[ $NAMES == "$want " ]] && return 0
    sleep 0.5
  done
  fail "$2: the view lists '$NAMES', expected '$want'"
}

run_case() {
  local mode=$1 group=$2 dir="$WORK/$1"
  mkdir -p "$dir"
  head -c 2000 /dev/zero > "$dir/a.txt"
  echo > "$dir/grow.txt"
  open_thunar "$dir"
  CUR=$WID
  xdotool windowsize --sync "$CUR" "$W" "$H"
  wait_title "$CUR" "$mode"
  sleep 1

  first_row_is grow.txt "$mode, before the size change"
  shot "$CUR" "before-size-$mode" "Sorted by size, the 1-byte grow.txt is the first row, above the 2 kB a.txt"
  head -c 5000 /dev/zero >> "$dir/grow.txt"
  first_row_is a.txt "$mode, after grow.txt grew to 5 kB"
  shot "$CUR" "after-size-$mode" "After grow.txt grew to 5 kB, the view re-sorted it below a.txt and shows its new size"
  pair "size-$mode" "Appended 5000 bytes to grow.txt while the details view, sorted by size, showed its folder" \
    "A file change in the shown folder reaches the view: the row re-sorts by its new size" \
    "grow.txt 1 byte, first row" "grow.txt 5 kB, below a.txt" "$group"

  echo hi > "$dir/.tmp-x"
  sleep 2
  listed_are "a.txt grow.txt" "$mode, with the hidden .tmp-x"
  shot "$CUR" "before-rename-$mode" "With the hidden temp file .tmp-x in the folder, the view lists only a.txt and grow.txt"
  mv "$dir/.tmp-x" "$dir/x.txt"
  listed_are "a.txt grow.txt x.txt" "$mode, after .tmp-x was renamed to x.txt"
  shot "$CUR" "after-rename-$mode" "After .tmp-x was renamed to x.txt, x.txt appears in the view"
  pair "rename-$mode" "Created the hidden .tmp-x, waited 2 s, then renamed it to x.txt" \
    "A hidden temp file renamed to a visible name appears in the details view" \
    "a.txt and grow.txt, .tmp-x hidden" "x.txt listed too" "$group"
}

open_thunar "$DEST_DIR" >>"$TLOG" 2>&1
DEST=$WID
wait_title "$DEST" dest

run_case off 'Details view, Expandable Folders off'

xfconf-query -c thunar -p /misc-expandable-folders -s true
sleep 1
run_case on 'Details view, Expandable Folders on'

sleep 1
kill -0 "$THUNAR_PID" || fail "Thunar is no longer running"
! grep -q "detached node" "$TLOG" || fail "Thunar logged $(grep -c 'detached node' "$TLOG") 'detached node' messages"
grep -q . "$TLOG" && { echo "Thunar log:"; tail -n 10 "$TLOG"; }
exit 0
