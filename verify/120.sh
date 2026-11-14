#!/bin/bash
# Issue #120: after a click on blank space clears the selection, Up/Down/Home/End select the file at the cursor
# even when the cursor can't move.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
BLANK_X=500
BLANK_Y=500
ONE="$WORK/one"
MANY="$WORK/many"
DEST_DIR="$WORK/dest"
SENT_DIR="$WORK/sent"

mkdir -p "$ONE" "$MANY" "$DEST_DIR" "$SENT_DIR"
echo sentinel > "$SENT_DIR/sentinel"
echo only > "$ONE/only.txt"
echo a > "$MANY/a.txt"
echo b > "$MANY/b.txt"
echo c > "$MANY/c.txt"

xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView
xfconf-query -c thunar -p /misc-expandable-folders -n -t bool -s true

keys() {
  focus "$CUR"
  local k
  for k in "$@"; do
    xdotool key "$k"
    sleep 0.2
  done
  sleep 0.3
}

deselect() {
  focus "$CUR"
  xdotool mousemove --window "$CUR" "$BLANK_X" "$BLANK_Y"
  sleep 0.2
  xdotool click 1
  sleep 0.3
  selected_is sentinel
}

N=0
CLIP=''
selected_is() {
  local want=$1 got='' i
  N=$((N + 1))
  if [[ $CLIP != sentinel ]]; then
    focus "$SENT"
    xdotool key ctrl+c
    sleep 0.1
  fi
  focus "$CUR"
  xdotool key ctrl+c
  focus "$DEST"
  xdotool key ctrl+v
  for ((i = 0; i < 50; i++)); do
    got=$(ls -A "$DEST_DIR" | tr '\n' ' ')
    [[ $got == "$want " ]] && break
    sleep 0.1
  done
  sleep 0.2
  rm -f "$DEST_DIR"/*
  [[ $got == "$want " ]] || fail "check $N: the selection held '$got', expected '$want'"
  CLIP=$want
  focus "$CUR"
}

reselects() {
  local key=$1 want=$2
  deselect
  keys "$key"
  selected_is "$want"
}

open_thunar "$DEST_DIR"
DEST=$WID
wait_title "$DEST" dest
open_thunar "$SENT_DIR"
SENT=$WID
wait_title "$SENT" sent
sleep 0.5
focus "$SENT"
xdotool key ctrl+a
open_thunar "$ONE"
ONE_WID=$WID
xdotool windowsize --sync "$ONE_WID" "$W" "$H"
wait_title "$ONE_WID" one
open_thunar "$MANY"
MANY_WID=$WID
xdotool windowsize --sync "$MANY_WID" "$W" "$H"
wait_title "$MANY_WID" many
sleep 1

G='Details view, Expandable Folders on'

CUR=$ONE_WID
deselect
keys Down
selected_is only.txt
deselect
shot "$CUR" before-single-up "In a folder with one file, Down selected only.txt and a click on blank space deselected it; the cursor stays on it"
keys Up
selected_is only.txt
shot "$CUR" after-single-up "Up selected only.txt again, although the cursor could not move up"
pair single-up "Pressed Down, clicked blank space, then pressed Up" "Up selects the file at the cursor when it is the only file" "only.txt not selected, cursor on it" "only.txt selected" "$G"
reselects Down only.txt
reselects Home only.txt
reselects End only.txt

CUR=$MANY_WID
deselect
keys Home
selected_is a.txt
reselects Up a.txt
reselects Home a.txt
shot "$CUR" details-first "With the cursor on the first file a.txt, Up and Home after a blank-space click selected a.txt again"
keys End
selected_is c.txt
reselects Down c.txt
reselects End c.txt
shot "$CUR" details-last "With the cursor on the last file c.txt, Down and End after a blank-space click selected c.txt again"

xfconf-query -c thunar -p /misc-expandable-folders -s false
sleep 1

CUR=$ONE_WID
reselects Up only.txt
reselects Down only.txt
CUR=$MANY_WID
keys Home
reselects Up a.txt
keys End
reselects Down c.txt
shot "$CUR" expandable-off-last "With Expandable Folders off, Down after a blank-space click selected the last file c.txt again"

G='Icon view'

CUR=$MANY_WID
keys ctrl+1
sleep 1
keys Home
selected_is a.txt
deselect
shot "$CUR" before-icon-up "Icon view: Home selected the first file a.txt and a click on blank space deselected it; the cursor stays on it"
keys Up
selected_is a.txt
shot "$CUR" after-icon-up "Up selected a.txt again in the icon view, although the cursor could not move up"
pair icon-up "Pressed Home, clicked blank space, then pressed Up" "In the icon view, Up selects the first file at the cursor" "a.txt not selected, cursor on it" "a.txt selected" "$G"
reselects Home a.txt
keys End
reselects End c.txt
CUR=$ONE_WID
keys ctrl+1
sleep 1
reselects Down only.txt

CUR=$MANY_WID
keys ctrl+3
sleep 1
keys Home
reselects Up a.txt
shot "$CUR" compact-first "Compact view: with the cursor on the first file a.txt, Up after a blank-space click selected a.txt again"
