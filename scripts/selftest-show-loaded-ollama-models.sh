#!/usr/bin/env bash
# Regression test for the Ollama model detector used by primary-buffer-query.sh.
# It supplies two fake running model processes and a fake Ollama API so the test
# can verify that every model is returned without a local Ollama server.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR="$ROOT_DIR/profile/airootfs/usr/share/anios/skel/.config/hypr/hyprland/scripts/ai/show-loaded-ollama-models.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -x "$DETECTOR" ]] || fail "Ollama model detector is missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required to run the detector self-test"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-ollama-model-selftest.XXXXXX")"
cleanup() {
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox kept at: $SANDBOX" >&2
    return 0
  fi
  rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

FAKE_BIN="$SANDBOX/bin"
mkdir -p -- "$FAKE_BIN"

cat >"$FAKE_BIN/ps" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$*" == "-eo args=" ]] || { echo "unexpected ps arguments: $*" >&2; exit 2; }
[[ "${ANIOS_FAKE_NO_MODELS:-0}" == 1 ]] && exit 0
cat <<'PROCESSES'
ollama_llama_server --model /root/.ollama/models/blobs/sha256-aaa
ollama_llama_server --model /root/.ollama/models/blobs/sha256-bbb
PROCESSES
FAKE

cat >"$FAKE_BIN/curl" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
url=""
data=""
while (($#)); do
  case "$1" in
    --silent|--show-error|--fail) shift ;;
    -H|--header) shift 2 ;;
    -d|--data) data="${2:?missing request body}"; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  */api/tags)
    printf '%s\n' '{"models":[{"name":"llama3.2:latest"},{"name":"qwen2.5:latest"}]}'
    ;;
  */api/show)
    model="$(jq -er '.name' <<<"$data")"
    case "$model" in
      llama3.2:latest)
        printf '%s\n' '{"modelfile":"FROM /root/.ollama/models/blobs/sha256-aaa"}'
        ;;
      qwen2.5:latest)
        printf '%s\n' '{"modelfile":"FROM /root/.ollama/models/blobs/sha256-bbb"}'
        ;;
      *) echo "unexpected model: $model" >&2; exit 2 ;;
    esac
    ;;
  *) echo "unexpected curl URL: $url" >&2; exit 2 ;;
esac
FAKE

chmod +x "$FAKE_BIN/ps" "$FAKE_BIN/curl"
output="$(PATH="$FAKE_BIN:$PATH" "$DETECTOR" --json_output)"
if ! jq -e '
  length == 2 and
  .[0].model == "llama3.2:latest" and
  .[0].path == "/root/.ollama/models/blobs/sha256-aaa" and
  .[1].model == "qwen2.5:latest" and
  .[1].path == "/root/.ollama/models/blobs/sha256-bbb"
' <<<"$output" >/dev/null; then
  printf 'Detector output was not the expected two-model JSON array:\n%s\n' "$output" >&2
  fail "multiple running Ollama models must be detected independently"
fi
no_models="$(ANIOS_FAKE_NO_MODELS=1 PATH="$FAKE_BIN:$PATH" "$DETECTOR" --json_output)"
[[ "$no_models" == '[]' ]] || fail "JSON mode must return an empty array when no models are running"

pass "the detector returns all running models and an empty JSON array when none are running"
