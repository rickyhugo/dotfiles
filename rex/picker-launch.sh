#!/bin/sh
rows=$1
choice=$2
client=$3
runner=$4
snapshot=$5
shift 5

child=
starting=false
pending_signal=
pending_status=
# shellcheck disable=SC2329
stop_child() {
  if [ "$starting" = true ]; then
    pending_signal=$1
    pending_status=$2
    return
  fi
  trap '' HUP INT TERM
  if [ "$child" != "" ]; then
    kill -s "$1" "$child" 2>/dev/null
    wait "$child" 2>/dev/null
  fi
  exit "$2"
}

run_child() {
  starting=true
  "$@" <&0 &
  child=$!
  starting=false
  if [ "$pending_signal" != "" ]; then
    stop_child "$pending_signal" "$pending_status"
  fi
  wait "$child"
  status=$?
  child=
  return "$status"
}

trap 'rm -f -- "$rows" "$choice"' 0
trap 'stop_child HUP 129' HUP
# Async children may inherit SIGINT ignored, so cancellation uses TERM.
trap 'stop_child TERM 130' INT
trap 'stop_child TERM 143' TERM

{
  FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' run_child "$@"
  status=$?
} <"$rows" >"$choice" || exit $?
case $status in
0)
  run_child "$REX_BIN_DIR/rex" --autostart=false -C "$client" 'do' "$runner" --args "$snapshot"
  exit $?
  ;;
1 | 130) exit 0 ;;
*) exit "$status" ;;
esac
