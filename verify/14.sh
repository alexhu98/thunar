#!/bin/bash
# Issue #14: file-operation dialogs don't take the keyboard focus, and a stray Enter doesn't cancel the job.
set -euo pipefail
. .github/scripts/verify-lib.sh

SRC="$WORK/src"
DST="$WORK/dst"
mkdir -p "$SRC" "$DST"
echo new > "$SRC/report.txt"
echo "old version of the report" > "$DST/report.txt"
xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView

F='Dialogs open without taking the focus'
K='Keys in the dialog'

find_window() {
  local i w
  for ((i = 0; i < 50; i++)); do
    w=$(xdotool search --onlyvisible --name "^$1\$" 2>/dev/null | head -1) || true
    [[ -n $w ]] && { echo "$w"; return 0; }
    sleep 0.2
  done
  return 1
}

gone() {
  local i
  for ((i = 0; i < 50; i++)); do
    xdotool search --onlyvisible --name "^$1\$" >/dev/null 2>&1 || return 0
    sleep 0.2
  done
  return 1
}

dst_is() {
  [[ $(cat "$DST/report.txt") == "$1" ]] || fail "$2: report.txt in dst holds '$(cat "$DST/report.txt")', expected '$1'"
}

editor_keys() {
  grep -c 'keysym 0xff0d, Return' "$WORK/editor.log" || true
}

copy_into_dst() {
  dbus-send --session --print-reply --reply-timeout=10000 --dest=org.xfce.FileManager /org/xfce/FileManager \
    org.xfce.FileManager.CopyInto string:"$WORK" array:string:"$SRC/report.txt" string:"$DST" string:"" string:"" >/dev/null \
    || fail "the D-Bus CopyInto call failed"
}

open_thunar "$DST"
MAIN=$WID
xdotool windowsize --sync "$MAIN" 700 450
xdotool windowmove --sync "$MAIN" 0 0
wait_title "$MAIN" dst

stdbuf -oL xev -name editor -geometry 560x300+700+460 > "$WORK/editor.log" 2>&1 &
EDITOR_WID=$(find_window editor) || fail "the xev window (the other app being typed in) did not appear"
focus "$EDITOR_WID"
sleep 0.5
[[ $(xdotool getactivewindow) == "$EDITOR_WID" ]] || fail "the editor window could not be focused"
mkdir -p "$WORK/many" "$WORK/more" "$WORK/copies"
(cd "$WORK/many" && seq -f 'file-%g' 30000 | xargs touch)
(cd "$WORK/more" && seq -f 'file-%g' 5000 | xargs touch)
dbus-send --session --print-reply --reply-timeout=10000 --dest=org.xfce.FileManager /org/xfce/FileManager \
  org.xfce.FileManager.CopyInto string:"$WORK" array:string:"$WORK/many" string:"$WORK/copies" string:"" string:"" >/dev/null \
  || fail "the D-Bus CopyInto call for the folder of 30000 files failed"
find_window 'File Operation Progress' >/dev/null || fail "the progress window did not appear during the copy of 30000 files"
ACTIVE=$(xdotool getactivewindow)
[[ $ACTIVE == "$EDITOR_WID" ]] || fail "the progress window of a long copy took the focus: window $ACTIVE ('$(xdotool getwindowname "$ACTIVE")') is active"
dbus-send --session --print-reply --reply-timeout=10000 --dest=org.xfce.FileManager /org/xfce/FileManager \
  org.xfce.FileManager.CopyInto string:"$WORK" array:string:"$WORK/more" string:"$WORK/copies" string:"" string:"" >/dev/null \
  || fail "the D-Bus CopyInto call for the second folder failed"
sleep 1
ACTIVE=$(xdotool getactivewindow)
[[ $ACTIVE == "$EDITOR_WID" ]] || fail "a second copy started with the progress window shown took the focus: window $ACTIVE ('$(xdotool getwindowname "$ACTIVE")') is active"
shot root progress-without-focus "During a copy of 30000 files with no question, the File Operation Progress window appeared after 500 ms, a second copy started while it was shown raised it, and the editor kept the focus"
for ((i = 0; i < 300; i++)); do
  xdotool search --onlyvisible --name '^File Operation Progress$' >/dev/null 2>&1 || break
  sleep 0.2
done
(( i < 300 )) || fail "the copies of 30000 and 5000 files did not finish within 60 s"
(( $(ls "$WORK/copies/many" | wc -l) == 30000 && $(ls "$WORK/copies/more" | wc -l) == 5000 )) || fail "the copies of 30000 and 5000 files are incomplete"
rm -rf "$WORK/many" "$WORK/more" "$WORK/copies"
[[ $(xdotool getactivewindow) == "$EDITOR_WID" ]] || fail "the editor lost the focus during the long copy"

shot root before-replace-dialog "The xev window 'editor' (another app, standing in for an editor) has the focus, before Thunar is asked over D-Bus to copy report.txt onto an existing one"

copy_into_dst
ASK=$(find_window 'Confirm to replace files') || fail "the replace dialog did not appear"
PROGRESS=$(find_window 'File Operation Progress') || fail "the progress window did not appear"
sleep 1
ACTIVE=$(xdotool getactivewindow)
[[ $ACTIVE == "$EDITOR_WID" ]] || fail "the focus moved to window $ACTIVE ('$(xdotool getwindowname "$ACTIVE")') when the dialogs opened"

before=$(editor_keys)
xdotool type --delay 30 'still typing'
xdotool key Return
sleep 1
(( $(editor_keys) > before )) || fail "the editor did not receive the Return pressed after the dialog opened"
find_window 'Confirm to replace files' >/dev/null || fail "the Return typed in the editor closed the replace dialog"
dst_is "old version of the report" "after typing in the editor"
[[ $(xdotool getactivewindow) == "$EDITOR_WID" ]] || fail "the editor lost the focus while typing"
shot root after-replace-dialog "The replace dialog and the progress window are open above Thunar, the editor kept the focus, and the Return typed there reached it"
pair replace-dialog "Asked Thunar over D-Bus to copy report.txt onto an existing one, then typed text and Return in the editor" "The progress window and the replace dialog open without taking the focus, and Enter typed elsewhere leaves the job alone" "editor focused" "dialogs open, editor still focused" "$F"

focus "$ASK"
xdotool key Return
sleep 1
find_window 'Confirm to replace files' >/dev/null || fail "Return in the focused replace dialog closed it: the dialog has a default button"
dst_is "old version of the report" "after Return in the replace dialog"
shot "$ASK" enter-in-dialog "Return pressed in the focused replace dialog did nothing: no button is the default, the dialog is still open and the file is unchanged"

xdotool key Tab Tab
shot "$ASK" cancel-focused "Two Tab presses from the dialog's text moved the focus past the Apply check box to Cancel, which shows the focus ring; no other button is highlighted"
xdotool key Return
gone 'Confirm to replace files' || fail "Return on the focused Cancel button did not close the replace dialog"
gone 'File Operation Progress' || fail "Return on Cancel did not cancel the job: the progress window stays open"
dst_is "old version of the report" "after Cancel"

next_copy() {
  focus "$EDITOR_WID"
  sleep 0.5
  copy_into_dst
  ASK=$(find_window 'Confirm to replace files') || fail "the replace dialog did not appear $1"
  find_window 'File Operation Progress' >/dev/null || fail "the progress window did not reappear $1"
  sleep 1
  ACTIVE=$(xdotool getactivewindow)
  [[ $ACTIVE == "$EDITOR_WID" ]] || fail "$1, the focus moved to window $ACTIVE ('$(xdotool getwindowname "$ACTIVE")')"
}

next_copy "the second time"
shot root reopened-without-focus "After the first job was cancelled and its progress window closed, a second copy shows the progress window and replace dialog again, and the editor keeps the focus"
focus "$ASK"
xdotool key Escape
gone 'Confirm to replace files' || fail "Escape did not close the replace dialog"
gone 'File Operation Progress' || fail "Escape did not cancel the job: the progress window stays open"
dst_is "old version of the report" "after Escape"

focus "$EDITOR_WID"
sleep 0.5
dbus-send --session --print-reply --reply-timeout=10000 --dest=org.xfce.FileManager /org/xfce/FileManager \
  org.xfce.FileManager.CopyInto string:"$WORK" array:string:"$SRC/missing.txt" string:"$DST" string:"" string:"" >/dev/null \
  || fail "the D-Bus CopyInto call for a missing file failed"
ERR=$(find_window Error) || fail "copying a missing file showed no error dialog"
sleep 1
ACTIVE=$(xdotool getactivewindow)
[[ $ACTIVE == "$EDITOR_WID" ]] || fail "the job error dialog took the focus: window $ACTIVE ('$(xdotool getwindowname "$ACTIVE")') is active"
before=$(editor_keys)
xdotool key Return
sleep 1
(( $(editor_keys) > before )) || fail "the editor did not receive the Return pressed after the error dialog opened"
find_window Error >/dev/null || fail "the Return typed in the editor closed the job error dialog"
shot root error-without-focus "Copying a missing file opened the job error dialog over Thunar, and the editor kept the focus and received the Return typed after it"
focus "$ERR"
xdotool key Escape
for ((i = 0; i < 25; i++)); do
  xdotool search --onlyvisible --pid "$THUNAR_PID" 2>/dev/null | grep -qx "$ERR" || break
  sleep 0.2
done
(( i < 25 )) || fail "Escape did not close the job error dialog"

next_copy "the third time"
focus "$ASK"
shot root before-replace-button "The focused replace dialog of a third copy, with Cancel, Skip, Rename and Replace in their usual order; Thunar shows the old 26-byte report.txt"
xdotool key alt+r
gone 'Confirm to replace files' || fail "Alt+R (Replace) did not close the replace dialog"
for ((i = 0; i < 25; i++)); do [[ $(cat "$DST/report.txt") == new ]] && break; sleep 0.2; done
dst_is new "after Replace"
focus "$MAIN"
xdotool key F5
sleep 1
shot root after-replace-button "Replace still works: the dialog closed and Thunar lists report.txt at 4 bytes, the copied file"
pair replace-button "Focused the replace dialog and pressed Alt+R (Replace)" "The dialog's buttons still work as before: Replace copies the file" "replace dialog focused" "report.txt replaced" "$K"
