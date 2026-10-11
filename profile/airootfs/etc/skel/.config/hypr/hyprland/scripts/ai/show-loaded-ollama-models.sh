#!/bin/bash

# From strikeoncmputrz/LLM_Scripts
# License: Apache-2.0, can be found in the same folder as this script

set -o pipefail

ollama_url="http://localhost"
port="11434"
json_out=0
blobs=()
model_names=()
model_paths=()

usage() {
    cat <<EOF
Identifies Ollama models running on this operating system by parsing running processes.

Usage: $0 [options]

Options:
  -j, --json_output        Print a JSON array instead of human-readable output.
  -p, --port PORT          Specify the Ollama server port (default: 11434).
  -u, --ollama_url URL     Specify the Ollama server host (default: http://localhost).
  -h, --help               Show this help.

Dependencies: curl, jq, ps, awk
EOF
}

while (($#)); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -j|--json_output)
            json_out=1
            shift
            ;;
        -u|--ollama_url)
            if (($# < 2)) || [[ -z "$2" ]]; then
                echo "Option $1 requires a URL." >&2
                exit 2
            fi
            ollama_url=$2
            shift 2
            ;;
        -p|--port)
            if (($# < 2)) || [[ ! "$2" =~ ^[0-9]{1,5}$ ]]; then
                echo "Option $1 requires a port number between 1 and 65535." >&2
                exit 2
            fi
            port=$2
            port_number=$((10#$port))
            if ((port_number < 1 || port_number > 65535)); then
                echo "Port must be between 1 and 65535." >&2
                exit 2
            fi
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

base_url="${ollama_url%/}:$port"

# The Ollama runner command line includes one --model PATH pair per loaded
# model. Read each argument independently; assigning command output directly to
# an array collapses all processes into one newline-containing string.
mapfile -t blobs < <(
    ps -eo args= 2>/dev/null | awk '
        {
            for (i = 1; i < NF; i++) {
                if ($i == "--model") {
                    print $(i + 1)
                    break
                }
            }
        }
    '
)

if ((${#blobs[@]} == 0)); then
    if ((json_out)); then
        printf '[]\n'
    else
        printf '\nWarning: No running Ollama models detected!\n\n'
    fi
    exit 0
fi

if ((!json_out)); then
    printf '\nConnecting to %s\n\n' "$base_url"
    if ! curl --silent --show-error --fail "$base_url" >/dev/null; then
        printf 'Could not connect to Ollama. Check the URL and that the server is running.\n' >&2
        exit 1
    fi
fi

if ! tags="$(curl --silent --show-error --fail "$base_url/api/tags")"; then
    if ((json_out)); then
        printf '[]\n'
        exit 0
    fi
    printf 'Could not retrieve the Ollama model list.\n' >&2
    exit 1
fi
if ! jq -e '(.models | type) == "array"' <<<"$tags" >/dev/null; then
    if ((json_out)); then
        printf '[]\n'
        exit 0
    fi
    printf 'Ollama returned an invalid model list.\n' >&2
    exit 1
fi

mapfile -t available_models < <(jq -r '.models[]?.name // empty' <<<"$tags")
for model in "${available_models[@]}"; do
    request="$(jq -cn --arg name "$model" '{name: $name, modelfile: true}')"
    if ! response="$(curl --silent --show-error --fail \
        -H 'Content-Type: application/json' \
        -d "$request" "$base_url/api/show")"; then
        continue
    fi
    model_path="$(jq -r '
        ((.modelfile // "")
        | split("\n")
        | map(select(startswith("FROM ")))
        | .[0] // "")
        | sub("^FROM[[:space:]]+"; "")
    ' <<<"$response" 2>/dev/null)" || continue
    [[ -n "$model_path" ]] || continue
    model_names+=("$model")
    model_paths+=("$model_path")
done

matching_models=()
for ((i = 0; i < ${#model_names[@]} && i < ${#model_paths[@]}; i++)); do
    for blob in "${blobs[@]}"; do
        if [[ "${model_paths[i]}" == "$blob" ]]; then
            matching_models+=("$(jq -cn \
                --arg model "${model_names[i]}" \
                --arg path "${model_paths[i]}" \
                '{model: $model, path: $path}')")
            break
        fi
    done
done

if ((json_out)); then
    if ((${#matching_models[@]} == 0)); then
        printf '[]\n'
    else
        printf '%s\n' "${matching_models[@]}" | jq -c -s '.'
    fi
elif ((${#matching_models[@]} == 0)); then
    printf '\nNo running Ollama model matched its local model file.\n\n'
else
    printf '\nModels Found:\n'
    printf '%s\n' "${matching_models[@]}" | jq -r '"  \(.model) (\(.path))"'
    printf '\n'
fi
