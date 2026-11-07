#!/bin/bash
# Issue #22: a search word that starts with ! excludes names that contain the rest of it.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
DIR="$WORK/files"

mkdir -p "$DIR"
for f in a-b.txt ab.txt draft-report.txt report.txt 'bang!name.txt'; do
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

cancel_search() {
  focus "$WID"
  xdotool key Escape
  sleep 1
}

results_are() {  # check name, the files the search must list
  local dest="$WORK/check-$1" got want i
  shift
  mkdir -p "$dest"
  focus "$WID"
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 100)) click 1
  sleep 0.5
  xdotool key ctrl+a ctrl+c
  sleep 0.5
  cancel_search
  go "$dest"
  xdotool key ctrl+v
  want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | sort | tr '\n' ' ')
    [[ $got == "$want" ]] && return 0
    sleep 0.2
  done
  fail "the search listed '$got', expected '$want'"
}

open_thunar "$DIR"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" files
focus "$WID"
xdotool key ctrl+2
sleep 0.5

E='A !word excludes names that contain it'

search -
shot "$WID" before-exclude "Searching files for - lists only the two names with a dash: a-b.txt and draft-report.txt"
results_are dash a-b.txt draft-report.txt
go "$DIR"
search '!-'
shot "$WID" after-exclude "Searching files for !- lists only the names without a dash: ab.txt, report.txt and bang!name.txt"
pair exclude "Searched files for !- instead of -" "A query made only of !- lists every name without a dash, and - alone still finds the dashes" "- lists a-b.txt and draft-report.txt" "!- lists ab, report and bang!name" "$E"
results_are exclude ab.txt 'bang!name.txt' report.txt

go "$DIR"
search report
shot "$WID" before-report "Searching files for report lists both draft-report.txt and report.txt"
results_are report draft-report.txt report.txt
go "$DIR"
search 'report !draft'
shot "$WID" after-report "Searching files for report !draft lists only report.txt"
pair report "Searched files for report !draft instead of report" "A !word after a plain word drops the names that contain it" "report lists draft-report and report" "report !draft lists only report.txt" "$E"
results_are report-draft report.txt

go "$DIR"
search '\!name'
shot "$WID" literal "Searching files for \\!name lists only bang!name.txt: an escaped ! is searched as literal text"
results_are literal 'bang!name.txt'

go "$DIR"
search '!'
results_are lone 'bang!name.txt'
