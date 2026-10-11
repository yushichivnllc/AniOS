#!/usr/bin/env bash
# Print mkarchiso file_permissions entries for executable AniOS skeleton files.
# mkarchiso copies the airootfs with mode bits stripped; these entries restore
# the executable files in the live user's home, /etc/skel, and the source skel.
set -Eeuo pipefail

if (($# != 1)) || [[ ! -d "$1" ]]; then
  echo "Usage: $0 AIROOTFS_DIRECTORY" >&2
  exit 2
fi

airootfs="$(cd -- "$1" && pwd -P)"
paths=(
  "$airootfs/home/anios"
  "$airootfs/etc/skel"
  "$airootfs/usr/share/anios/skel"
)
for path in "${paths[@]}"; do
  [[ -d "$path" ]] || {
    echo "Missing skeleton directory: $path" >&2
    exit 1
  }
done

mapfile -d '' -t executable_files < <(find "${paths[@]}" -type f -perm /111 -print0 | sort -z)
declare -A seen=()
for file in "${executable_files[@]}"; do
  image_path="/${file#"$airootfs"/}"
  [[ -z "${seen[$image_path]+present}" ]] || {
    echo "Duplicate skeleton permission path: $image_path" >&2
    exit 1
  }
  seen["$image_path"]=present
  mode="$(stat -c '%a' -- "$file")"
  printf '%s:0:0:%s\n' "$image_path" "$mode"
done
