#!/bin/bash
# Installs the built .debs and proves them under Xvfb: verify-proof.sh install | run | publish
#   install  installs thunar, thunar-data and libthunarx-3-0 from dist/ and the test tools: from the debs cached in
#            $DEBS when they install cleanly and provide every tool, otherwise with apt from ppa:zorinos/stable,
#            which repairs what dpkg left. On that apt path, when the built version was already installed before
#            apt ran (apt then skips the local debs), dpkg -i installs them over it. $DEBS then keeps exactly the
#            installed versions of everything apt and dpkg added. Prints cached=true|false (for $GITHUB_OUTPUT).
#   run      runs the smoke test (Thunar is still running 10 s after launch), then each verify/<issue>.sh, each with
#            its own Xvfb, xfwm4 and D-Bus session, a fresh HOME and XDG folders, and a $TIMEOUT s limit. A script
#            that could end after $BUDGET s of the run is reported as not run, and one that passes with a before/after
#            pair that has no pair call fails. Numbers the shots and makes each pair's 1920px image
#            (verify-shots.py build). Writes the shots, $OUT/pairs/, the logs, $OUT/results.tsv, $OUT/numbered.json,
#            the manifest $OUT/verify.tsv and, last, $OUT/complete, and fails if any test failed.
#   publish  commits the shots, the pair images and the manifest to the shots branch under pr-$PR/
#            (verify-<test>-<shot>.png, pair-<test>-<what>.png, verify.tsv) through shots.sh, writes the verify
#            comment through pr-comment.sh and then the summary through pr-summary.py. Run it whether or not run
#            passed. A failed upload is marked in the comment and in the manifest (file -), and publish then fails.
# Env: PR, HEAD_SHA, HEAD_REF, GH_REPO, RUN_ID, RUN_URL, OUT, DEBS, TIMEOUT (default 120), BUDGET (default 900).
# DRY_RUN=1 makes publish print the comment instead of uploading and posting it.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/verify-proof}
DEBS=${DEBS:-$HOME/verify-debs}
TIMEOUT=${TIMEOUT:-120}
BUDGET=${BUDGET:-900}
TOOLS=(xvfb xfwm4 xdotool imagemagick x11-utils dbus gvfs gvfs-daemons zorin-desktop-themes)
mkdir -p "$OUT"

install() {
  local debs=(dist/thunar_*.deb dist/thunar-data_*.deb dist/libthunarx-3-0_*.deb) deb
  for deb in "${debs[@]}"; do
    [[ -f $deb ]] || { echo "::error::no $deb; the build job's debs artifact goes in dist/" >&2; exit 1; }
  done
  sudo rm -f /var/lib/man-db/auto-update
  local repair=0
  if compgen -G "$DEBS/*.deb" >/dev/null; then
    if sudo dpkg -i "$DEBS"/*.deb "${debs[@]}" >"$OUT/dpkg.log" 2>&1 && dpkg -s "${TOOLS[@]}" >/dev/null 2>&1; then
      echo "installed from $(compgen -G "$DEBS/*.deb" | wc -l) cached debs" >&2
      echo cached=true
      return
    fi
    echo "::warning::the cached debs did not install cleanly; installing with apt" >&2
    tail -n 5 "$OUT/dpkg.log" >&2
    repair=1
  fi
  sudo add-apt-repository -y ppa:zorinos/stable >&2
  mkdir -p "$DEBS"
  local apt=(sudo apt-get -y --no-install-recommends -o Dir::Cache::Archives="$DEBS" -o APT::Sandbox::User=root)
  local built had
  built=$(dpkg-deb --show --showformat='${Version}' "${debs[0]}")
  had=$(dpkg-query -W -f='${db:Status-Abbrev}${Version}' thunar 2>/dev/null || true)
  (( repair == 0 )) || "${apt[@]}" -f install >&2
  "${apt[@]}" install "${debs[@]/#/./}" "${TOOLS[@]}" >&2
  [[ $had != "ii $built" ]] || sudo dpkg -i "${debs[@]}" >&2
  sudo rm -rf "$DEBS/partial" "$DEBS/lock"
  sudo chown -R "$(id -u):$(id -g)" "$DEBS"
  local pkg ver
  for deb in "$DEBS"/*.deb; do
    [[ -f $deb ]] || continue
    read -r pkg ver < <(dpkg-deb --show --showformat='${Package} ${Version}\n' "$deb")
    [[ $(dpkg-query -W -f='${db:Status-Abbrev}${Version}' "$pkg" 2>/dev/null) == "ii $ver" ]] || rm -f "$deb"
  done
  echo "cached $(compgen -G "$DEBS/*.deb" | wc -l) debs in $DEBS" >&2
  echo cached=false
}

theme() {
  if [[ -d /usr/share/themes/ZorinBlue-Dark/gtk-3.0 ]]; then echo ZorinBlue-Dark; else echo Adwaita:dark; fi
}

smoke() {
  . "$HERE/verify-lib.sh"
  mkdir -p "$WORK/Documents" "$WORK/Pictures"
  echo hello > "$WORK/notes.txt"
  open_thunar "$WORK"
  wait_title "$WID" "$(basename "$WORK")"
  sleep 10
  kill -0 "$THUNAR_PID" 2>/dev/null || fail "Thunar exited within 10 s of launch"
  shot "$WID" window "Thunar is still running 10 s after launch, with its window open on a folder of 2 folders and a file"
}

session() {
  local i
  Xvfb -displayfd 3 -screen 0 1280x800x24 -nolisten tcp 3>"$XDG_RUNTIME_DIR/display" >"$XVFB_LOG" 2>&1 &
  for ((i = 0; i < 100; i++)); do
    [[ -s $XDG_RUNTIME_DIR/display ]] && break
    sleep 0.1
  done
  [[ -s $XDG_RUNTIME_DIR/display ]] || { cat "$XVFB_LOG" >&2; echo "FAIL: Xvfb did not start" >&2; return 1; }
  DISPLAY=:$(cat "$XDG_RUNTIME_DIR/display")
  export DISPLAY
  dbus-update-activation-environment DISPLAY || echo "warning: services that D-Bus starts won't get DISPLAY" >&2
  xfwm4 --compositor=off --sm-client-disable &
  for ((i = 0; i < 50; i++)); do
    xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id' && break
    sleep 0.1
  done
  "$@"
}

test_one() {  # name, command...
  local name=$1 dir="$OUT/run/$1" start pid status
  shift
  rm -rf "$dir" "$OUT/shots/$name"
  mkdir -p "$dir/home" "$dir/work" "$dir/runtime" "$OUT/shots/$name"
  chmod 700 "$dir/runtime"
  start=$SECONDS
  HOME=$dir/home XDG_CONFIG_HOME=$dir/home/.config XDG_CACHE_HOME=$dir/home/.cache XDG_DATA_HOME=$dir/home/.local/share \
    XDG_STATE_HOME=$dir/home/.local/state XDG_RUNTIME_DIR=$dir/runtime \
    WORK=$dir/work SHOTS=$OUT/shots/$name XVFB_LOG=$OUT/logs/$name.xvfb.log GTK_THEME=$(theme) NO_AT_BRIDGE=1 \
    timeout -k 5 "$TIMEOUT" dbus-run-session -- "$HERE/verify-proof.sh" session "$@" >"$OUT/logs/$name.log" 2>&1 </dev/null &
  pid=$!
  wait "$pid" && status=0 || status=$?
  if (( status == 0 )) && ! python3 "$HERE/verify-shots.py" check "$OUT/shots/$name" >>"$OUT/logs/$name.log" 2>&1; then
    status="pairs incomplete"
  elif (( status == 0 )); then
    status=pass
  elif (( status == 124 || status == 137 )); then
    status="timeout ${TIMEOUT}s"
  else
    status="exit $status"
  fi
  kill -- -"$pid" 2>/dev/null || true
  printf '%s\t%s\t%s\n' "$name" "$status" $((SECONDS - start)) >> "$OUT/results.tsv"
  echo "$name: $status in $((SECONDS - start)) s"
  [[ $status == pass ]] || sed 's/^/  | /' "$OUT/logs/$name.log" | tail -n 30
}

not_run() {  # name, status, reason
  echo "FAIL: $3" > "$OUT/logs/$1.log"
  printf '%s\t%s\t0\n' "$1" "$2" >> "$OUT/results.tsv"
  echo "$1: $2"
}

run() {
  rm -rf "$OUT/logs" "$OUT/run" "$OUT/shots" "$OUT/pairs" "$OUT/complete" "$OUT/verify.tsv" "$OUT/numbered.json"
  mkdir -p "$OUT/logs"
  : > "$OUT/results.tsv"
  theme > "$OUT/theme"
  local script name begin=$SECONDS
  test_one smoke smoke
  for script in verify/*.sh; do
    [[ -f $script ]] || continue
    name=$(basename "$script" .sh)
    if [[ ! $name =~ ^[0-9]+$ ]]; then
      not_run "$name.sh" misnamed "$script is not named verify/<issue>.sh, so it was not run"
    elif (( SECONDS - begin + TIMEOUT > BUDGET )); then
      not_run "$name" "not run (time budget)" "$script could end after the run's ${BUDGET} s budget, so it was not run"
    else
      test_one "$name" bash "$script"
    fi
  done
  python3 "$HERE/verify-shots.py" build "$OUT" || echo "::warning::some pair images could not be made" >&2
  : > "$OUT/complete"
  local failed
  failed=$(awk -F'\t' '$2 != "pass"' "$OUT/results.tsv" | wc -l)
  echo "$(( $(wc -l < "$OUT/results.tsv") - failed )) of $(wc -l < "$OUT/results.tsv") passed"
  (( failed == 0 )) || exit 1
}

upload() {  # local file, path on shots -> commit sha
  OUT="$OUT/upload" "$HERE/shots.sh" "$1" "$2" "Verify screenshots for PR #${PR:-0}" </dev/null
}

publish() {
  [[ -n ${PR:-} || ${DRY_RUN:-0} == 1 ]] || { echo "publish needs PR" >&2; exit 1; }
  : "${GH_REPO:?}"
  : > "$OUT/urls.tsv"
  local file path sha url failed=0
  export SHOTS_DEADLINE=$(( $(date +%s) + 300 ))
  if [[ -s $OUT/results.tsv && ! -s $OUT/numbered.json ]]; then
    python3 "$HERE/verify-shots.py" build "$OUT" || echo "::warning::some pair images could not be made" >&2
  fi
  if [[ -s $OUT/results.tsv && -s $OUT/numbered.json ]]; then
    while IFS=$'\t' read -r file path; do
      if [[ -s $OUT/$file ]] && sha=$(upload "$OUT/$file" "pr-${PR:-0}/$path"); then
        url="https://github.com/$GH_REPO/blob/$sha/pr-${PR:-0}/$path?raw=true"
      else
        echo "::error::could not upload pr-${PR:-0}/$path" >&2
        url=- failed=1
      fi
      printf '%s\t%s\n' "$file" "$url" >> "$OUT/urls.tsv"
    done < <(jq -r '.[] | (.test as $t | .shots[] | [.file, "verify-\($t)-\(.name).png"]), (select(.kind == "pair" and .image) | [.image, "pair-\(.test)-\(.what).png"]) | @tsv' "$OUT/numbered.json")
    python3 "$HERE/verify-shots.py" manifest "$OUT" > "$OUT/verify-shots.tsv"
    if ! upload "$OUT/verify-shots.tsv" "pr-${PR:-0}/verify.tsv" >/dev/null; then
      echo "::error::could not upload pr-${PR:-0}/verify.tsv" >&2
      failed=1
    fi
  fi
  python3 "$HERE/verify-shots.py" comment "$OUT" > "$OUT/comment.md"
  OUT="$OUT/comment" "$HERE/pr-comment.sh" put verify "$OUT/comment.md"
  OUT="$OUT/summary" python3 "$HERE/pr-summary.py" || echo "::warning::could not update the summary comment" >&2
  return "$failed"
}

case ${1:-} in
  install) install ;;
  run) run ;;
  publish) publish ;;
  session) shift; session "$@" ;;
  smoke) smoke ;;
  *) echo "usage: $0 install | run | publish" >&2; exit 2 ;;
esac
