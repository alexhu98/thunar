#!/bin/bash
# Issues #40 and #41: every new split view opens at 50/50 instead of the saved pixel position (the old behaviour is
# behind the hidden misc-remember-split-position), and --split PERCENT opens a new window split at that ratio.
set -euo pipefail
. .github/scripts/verify-lib.sh

G1='New split views open at 50/50 (#40)'
G2='--split PERCENT (#41)'

for d in left alpha bravo charlie delta echo; do
  mkdir -p "$WORK/$d"
done

xfconf-query -c thunar -p /last-window-width -n -t int -s 1000
xfconf-query -c thunar -p /last-window-height -n -t int -s 700
xfconf-query -c thunar -p /last-window-maximized -n -t bool -s false
xfconf-query -c thunar -p /last-side-pane -n -t string -s THUNAR_SIDEPANE_TYPE_HIDDEN_SHORTCUTS
xfconf-query -c thunar -p /last-splitview-separator-position -n -t int -s 300
xfconf-query -c thunar -p /misc-open-new-window-as-tab -n -t bool -s true

saved() { xfconf-query -c thunar -p /last-splitview-separator-position 2>/dev/null || echo unset; }

windows() { xdotool search --all --onlyvisible --pid "$THUNAR_PID" --class Thunar 2>/dev/null | wc -l; }

# Finds the two empty file views (runs of one colour at least 80 px long) along a row at 3/4 of the window's height (h) or the column at its middle
# (v), and sets POS (the divider, from the first view's start) and SIZE (from the first view's start to the second's end).
measure() {  # png h|v
  local w h crop out
  read -r w h < <(identify -format '%w %h\n' "$1")
  if [[ $2 == h ]]; then crop="${w}x1+0+$((h * 3 / 4))"; else crop="1x${h}+$((w / 2))+0"; fi
  out=$(convert "$1" -crop "$crop" +repage -depth 8 txt:- | awk -F'[ ,:()]+' -v dir="$2" '
    NR == 1 { next }
    {
      i = (dir == "h") ? $1 : $2
      c = $3 "," $4 "," $5
      if (c != colour) { if (i - start >= 80) runs = runs " " start " " (i - 1); start = i; colour = c }
    }
    END { if (i + 1 - start >= 80) runs = runs " " start " " i; print runs }')
  read -r S1 E1 S2 E2 EXTRA <<<"$out"
  [[ -n ${E2:-} && -z ${EXTRA:-} ]] || fail "expected two empty file views along the $2 line of $1, found runs:$out"
  POS=$(((E1 + S2) / 2 - S1))
  SIZE=$((E2 - S1 + 1))
}

grab() {  # name: a capture of $WID only for measuring
  focus "$WID"
  sleep 1
  import -window "$WID" "$WORK/$1.png" || fail "could not capture window $WID"
  measure "$WORK/$1.png" "${2:-h}"
}

ratio_is() {  # percent what
  (( POS * 100 >= $1 * SIZE - 300 && POS * 100 <= $1 * SIZE + 300 )) \
    || fail "$2: the divider is at $POS of $SIZE px, expected $1% ($(( $1 * SIZE / 100 )) px, within 3 px)"
}

pos_is() {  # px what
  (( POS >= $1 - 3 && POS <= $1 + 3 )) || fail "$2: the divider is at $POS px, expected $1 px (within 3 px)"
}

drag_divider() {  # from-x to-x
  local y=350 s
  xdotool mousemove --window "$WID" "$1" "$y"
  sleep 0.3
  xdotool mousedown 1
  for ((s = 1; s <= 10; s++)); do
    xdotool mousemove --window "$WID" $(($1 + ($2 - $1) * s / 10)) "$y"
    sleep 0.05
  done
  xdotool mouseup 1
  sleep 0.5
  xdotool mousemove --window "$WID" 500 5
}

f3() {
  focus "$WID"
  xdotool key F3
  sleep 1
}

# #41 with Thunar not running
open_thunar --split 60 "$WORK/left"
wait_title "$WID" left
grab cold
ratio_is 60 "thunar --split 60 with Thunar not running"
shot "$WID" split-60-cold "With Thunar not running, thunar --split 60 left opened one window in split view, left in both panes, the left pane 60% wide"

# #40 with the hidden misc-remember-split-position on: upstream behaviour
xfconf-query -c thunar -p /misc-remember-split-position -n -t bool -s true
open_thunar -w "$WORK/alpha"
wait_title "$WID" alpha
f3
grab remember
pos_is 300 "F3 with misc-remember-split-position on"
shot "$WID" before-split-centered "With misc-remember-split-position on, F3 opened split view at the saved 300 px, left of the center"
drag_divider $((S1 + POS)) 400
(( $(saved) >= 390 && $(saved) <= 410 )) || fail "with misc-remember-split-position on, dragging to 400 saved $(saved)"
xfconf-query -c thunar -p /last-splitview-separator-position -s 300
xfconf-query -c thunar -p /misc-remember-split-position -s false

# #40 by default
open_thunar -w "$WORK/bravo"
wait_title "$WID" bravo
f3
grab centered
ratio_is 50 "F3 with last-splitview-separator-position at 300"
shot "$WID" after-split-centered "By default, F3 opened split view with the two panes of equal width, though the saved position is still 300 px"
pair split-centered "Pressed F3 in a new window with last-splitview-separator-position at 300, with misc-remember-split-position on, then off (the default)" \
  "New split views open at 50/50 unless the hidden setting asks for the saved pixel position" \
  "setting on: divider at the saved 300 px" "default: divider at 50/50" "$G1"

drag_divider $((S1 + POS)) 280
grab dragged
DRAGGED=$POS
(( DRAGGED >= 270 && DRAGGED <= 290 )) || fail "dragging the divider to 280 left it at $DRAGGED"
[[ $(saved) == 300 ]] || fail "a drag changed last-splitview-separator-position to $(saved)"
xdotool key ctrl+t
sleep 1
grab dragged-tab
pos_is "$DRAGGED" "after Ctrl+T in the window whose divider was dragged"
shot "$WID" drag-kept-with-tab "After dragging the divider to about 280 px and opening a tab with Ctrl+T, the divider stays at about 280 px"

open_thunar -w "$WORK/charlie"
wait_title "$WID" charlie
f3
grab centered-again
ratio_is 50 "F3 in a new window after a drag in another"
[[ $(saved) == 300 ]] || fail "last-splitview-separator-position is $(saved) after a drag, expected 300"

# #41 with Thunar running
EXISTING=$WID
EXISTING_POS=$POS
N=$(windows)
shot "$WID" before-split-60 "A running Thunar's window charlie, split 50/50, before thunar --split 60 delta"
open_thunar --split 60 "$WORK/delta"
wait_title "$WID" delta
[[ $WID != "$EXISTING" ]] || fail "thunar --split 60 didn't open a new window"
(( $(windows) == N + 1 )) || fail "thunar --split 60 opened $(( $(windows) - N )) windows, expected 1"
grab split-60
ratio_is 60 "thunar --split 60 with Thunar running and Open new windows as tabs on"
shot "$WID" after-split-60 "thunar --split 60 delta opened a new window, delta in both panes, the left pane 60% wide, with Open new windows as tabs on"
pair split-60 "Ran thunar --split 60 delta with Thunar running and Open new windows as tabs on" \
  "--split opens a new window split at the given percentage" "window charlie, split 50/50" "new window delta, split 60/40" "$G2"
[[ $(saved) == 300 ]] || fail "thunar --split 60 changed last-splitview-separator-position to $(saved)"
SPLIT=$WID
WID=$EXISTING
grab existing
pos_is "$EXISTING_POS" "the existing window after thunar --split 60"
WID=$SPLIT

open_thunar -w "$WORK/echo"
wait_title "$WID" echo
f3
grab after-split-option
ratio_is 50 "F3 in a new window after thunar --split 60"

for v in 5 95 abc; do
  N=$(windows)
  if thunar --split "$v" "$WORK/echo" 2> "$WORK/err.txt"; then
    fail "thunar --split $v succeeded"
  fi
  grep -qF 'Thunar: --split takes a percentage from 10 to 90' "$WORK/err.txt" || fail "thunar --split $v printed '$(cat "$WORK/err.txt")'"
  sleep 1
  (( $(windows) == N )) || fail "thunar --split $v opened a window"
done

if thunar --quit --split 5 2> "$WORK/err.txt"; then
  fail "thunar --quit --split 5 succeeded"
fi
grep -qF 'Thunar: --split takes a percentage from 10 to 90' "$WORK/err.txt" || fail "thunar --quit --split 5 printed '$(cat "$WORK/err.txt")'"
sleep 1
kill -0 "$THUNAR_PID" 2>/dev/null || fail "thunar --quit --split 5 quit Thunar"

help=$(thunar --help)
grep -q -- '--split=PERCENT' <<<"$help" || fail "thunar --help doesn't list --split"

open_thunar -t "$WORK/alpha" "$WORK/bravo" "$WORK/charlie" -T "$WORK/delta" --split 60
wait_title "$WID" alpha
grab tabs-right
ratio_is 60 "thunar -t alpha bravo charlie -T delta --split 60"

open_thunar -t "$WORK/alpha" "$WORK/bravo" --split 30
wait_title "$WID" alpha
grab tabs
ratio_is 30 "thunar -t alpha bravo --split 30"
focus "$WID"
xdotool mousemove --window "$WID" $((S2 + 100)) 500
sleep 0.2
xdotool click 1
xdotool mousemove --window "$WID" 500 5
sleep 0.5
wait_title "$WID" alpha
shot "$WID" split-30-tabs "thunar -t a b --split 30 opened tabs a and b in the left pane, a in the right pane, split 30/70; the click in the right pane shows a in the title"

xfconf-query -c thunar -p /misc-vertical-split-pane -n -t bool -s true
open_thunar -w "$WORK/echo"
wait_title "$WID" echo
f3
grab vertical v
ratio_is 50 "F3 with misc-vertical-split-pane on"
open_thunar --split 60 "$WORK/echo"
wait_title "$WID" echo
grab vertical-60 v
ratio_is 60 "thunar --split 60 with misc-vertical-split-pane on"
shot "$WID" split-60-vertical "With misc-vertical-split-pane on, thunar --split 60 echo opened a new window whose top pane takes 60% of the height"
[[ $(saved) == 300 ]] || fail "last-splitview-separator-position is $(saved) at the end, expected 300"
