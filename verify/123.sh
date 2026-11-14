#!/bin/bash
# Issue #123: Select by Pattern opens with the last pattern used, shared by every window until Thunar quits.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
DIR="$WORK/files"
G='Select by Pattern remembers the last pattern (#123)'

mkdir -p "$DIR"
for f in a-1pre.png a-2post.png b-2post.png; do echo "$f" > "$DIR/$f"; done

keys() {
  focus "$MAIN"
  local k
  for k in "$@"; do
    xdotool key "$k"
    sleep 0.3
  done
  sleep 0.3
}

open_dialog() {
  local i
  keys ctrl+s
  for ((i = 0; i < 25; i++)); do
    DLG=$(xdotool getactivewindow 2>/dev/null) || DLG=''
    [[ -n $DLG && $(xdotool getwindowname "$DLG" 2>/dev/null) == 'Select by Pattern' ]] && return 0
    sleep 0.2
  done
  fail "Ctrl+S opened no Select by Pattern dialog"
}

dialog_keys() {
  local k
  for k in "$@"; do
    xdotool key "$k"
    sleep 0.3
  done
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

open_thunar "$DIR"
MAIN=$WID
FIRST=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" files
sleep 1

open_dialog
dialog_keys alt+w alt+p
xdotool type --delay 20 '*-2post.png'
dialog_keys Return
selected_is a-2post.png b-2post.png

keys ctrl+a
selected_is a-1pre.png a-2post.png b-2post.png
shot "$MAIN" before-reuse "All three files are selected before Select by Pattern is opened again"
open_dialog
shot "$DLG" prefilled "The reopened dialog shows the last pattern *-2post.png, highlighted, with Match words off"
dialog_keys Return
selected_is a-2post.png b-2post.png
shot "$MAIN" after-reuse "Pressing Enter in the reopened dialog selected a-2post.png and b-2post.png again, without retyping"
pair reuse "Pressed Ctrl+S, then Enter, without typing a pattern" "The dialog reuses the last pattern, so Enter alone repeats the last select" "All 3 files selected" "a-2post.png, b-2post.png selected" "$G"

open_dialog
xdotool type --delay 20 'zzz'
dialog_keys Escape
keys ctrl+a
open_dialog
shot "$DLG" after-cancel "After typing zzz and cancelling, the dialog still shows *-2post.png"
dialog_keys Return
selected_is a-2post.png b-2post.png

open_thunar "$DIR"
MAIN=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" files
sleep 1
focus "$FIRST"
xdotool key ctrl+w
sleep 1
keys ctrl+a
open_dialog
shot "$DLG" second-window "In a second window, after the first one closed, the dialog still shows *-2post.png"
dialog_keys Return
selected_is a-2post.png b-2post.png
shot "$MAIN" second-window-selected "Enter in the second window's dialog selected a-2post.png and b-2post.png"
