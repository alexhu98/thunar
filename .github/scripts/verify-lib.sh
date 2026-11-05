# Helpers for verify/<issue>.sh and the smoke test, sourced: . .github/scripts/verify-lib.sh
#   open_thunar ARG...      runs thunar ARG..., waits for the new window, and sets WID (and THUNAR_PID on the first call;
#                           later calls hand ARG... to that instance, as Thunar does)
#   focus WID               raises and focuses the window, so that xdotool key and type (without --window) reach it
#   wait_title WID TEXT     waits until the window's title contains TEXT
#   shot WID NAME PROVES    saves the window as $SHOTS/NAME.png and adds "NAME<tab>PROVES" to $SHOTS/shots.tsv
#   fail MESSAGE            prints MESSAGE and exits 1
# verify-proof.sh run sets DISPLAY, HOME and the XDG folders, WORK (an empty folder for the test's files) and SHOTS.
# Shot names are lowercase letters, digits and -; a pair is before-<what> and after-<what>.

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

open_thunar() {
  local before='' i w
  if [[ -n ${THUNAR_PID:-} ]] && kill -0 "$THUNAR_PID" 2>/dev/null; then
    before=$(xdotool search --all --onlyvisible --pid "$THUNAR_PID" --class Thunar 2>/dev/null) || true
    thunar "$@" &
  else
    thunar "$@" &
    THUNAR_PID=$!
  fi
  for ((i = 0; i < 75; i++)); do
    for w in $(xdotool search --all --onlyvisible --pid "$THUNAR_PID" --class Thunar 2>/dev/null); do
      grep -qx "$w" <<<"$before" || { WID=$w; return 0; }
    done
    sleep 0.2
  done
  fail "no new Thunar window within 15 s"
}

focus() {
  xdotool windowactivate --sync "$1" || fail "could not focus window $1"
}

wait_title() {
  local wid=$1 text=$2 i
  for ((i = 0; i < 50; i++)); do
    [[ $(xdotool getwindowname "$wid" 2>/dev/null) == *"$text"* ]] && return 0
    sleep 0.2
  done
  fail "window title is '$(xdotool getwindowname "$wid" 2>/dev/null)', expected it to contain '$text'"
}

shot() {
  local wid=$1 name=$2 proves=$3
  [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "shot name '$name' must be lowercase letters, digits and -"
  [[ -n $proves && $proves != *[$'\t\n']* ]] || fail "shot $name needs a one-line sentence saying what it proves"
  sleep 1
  import -window "$wid" "$SHOTS/$name.png" || fail "could not capture window $wid as $name"
  printf '%s\t%s\n' "$name" "$proves" >> "$SHOTS/shots.tsv"
}
