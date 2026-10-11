#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-session"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

MOCK_BIN="$TMP_DIR/bin"
HOME_DIR="$TMP_DIR/home"
CONFIG_HOME="$TMP_DIR/xdg-config"
ARGS_LOG="$TMP_DIR/args"
ENV_LOG="$TMP_DIR/anios-desktop"
mkdir -p -- "$MOCK_BIN" "$HOME_DIR"

cat >"$MOCK_BIN/dbus-run-session" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >"$ANIOS_TEST_ARGS"
printf '%s\n' "${ANIOS_DESKTOP-<unset>}" >"$ANIOS_TEST_ENV"
MOCK
chmod +x -- "$MOCK_BIN/dbus-run-session"

run_session() {
  local requested_mode="$1"
  local inherited_mode="$2"
  local expected_environment="$3"
  shift 3
  local -a command=("$SESSION")
  [[ -z "$requested_mode" ]] || command+=("$requested_mode")
  command+=("$@")
  rm -f -- "$ARGS_LOG" "$ENV_LOG"
  env \
    HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$CONFIG_HOME" \
    PATH="$MOCK_BIN:/usr/bin:/bin" \
    ANIOS_TEST_ARGS="$ARGS_LOG" \
    ANIOS_TEST_ENV="$ENV_LOG" \
    ANIOS_DESKTOP="$inherited_mode" \
    "${command[@]}"
  [[ -s "$ARGS_LOG" && -s "$ENV_LOG" ]] || {
    echo "FAIL: session wrapper did not reach the mocked dbus-run-session" >&2
    exit 1
  }
  [[ "$(cat "$ARGS_LOG")" == $'--\nHyprland' ]] || {
    echo "FAIL: session wrapper passed unexpected arguments: $(cat "$ARGS_LOG")" >&2
    exit 1
  }
  [[ "$(cat "$ENV_LOG")" == "$expected_environment" ]] || {
    echo "FAIL: session passed ANIOS_DESKTOP='$(cat "$ENV_LOG")' instead of '$expected_environment'" >&2
    exit 1
  }
}

# Choosing a named SDDM session must replace an older preference, write to the
# same XDG_CONFIG_HOME used by the Hyprland config/switcher, and leave the mode
# file as the source of truth so `hyprctl reload` can switch modes in-session.
run_session --minimal imi '<unset>'
[[ "$(cat "$CONFIG_HOME/anios/desktop-mode")" == minimal ]] || {
  echo "FAIL: Minimal SDDM session did not persist its selected mode" >&2
  exit 1
}
[[ ! -e "$HOME_DIR/.config/anios/desktop-mode" ]] || {
  echo "FAIL: session wrapper ignored XDG_CONFIG_HOME" >&2
  exit 1
}

run_session --imi minimal '<unset>'
[[ "$(cat "$CONFIG_HOME/anios/desktop-mode")" == imi ]] || {
  echo "FAIL: Immaterial Impulse SDDM session did not persist its selected mode" >&2
  exit 1
}

# An unqualified AniOS session keeps the saved selection unchanged.
run_session "" minimal minimal
[[ "$(cat "$CONFIG_HOME/anios/desktop-mode")" == imi ]] || {
  echo "FAIL: default AniOS session unexpectedly changed the saved mode" >&2
  exit 1
}

echo "OK: SDDM session selection persists the correct desktop mode"
