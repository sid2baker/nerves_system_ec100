#!/usr/bin/env bash
# Fetch the external toolchain sources before spending time on the system build.
set -euo pipefail

cache=${1:?Usage: download-sources.sh CACHE_DIR}
manifest="$(dirname "$0")/toolchain-sources.sha512"
mkdir -p "$cache"

while read -r checksum url; do
    [[ -z "$checksum" || "$checksum" == \#* ]] && continue
    filename=${url##*/}
    echo "Source: $filename"
    if [[ ! -f "$cache/$filename" ]]; then
        curl --fail --location --silent --show-error \
            --connect-timeout 15 --max-time 300 \
            --speed-limit 1024 --speed-time 30 \
            --retry 2 --retry-all-errors \
            "$url" -o "$cache/$filename.part"
        printf '%s  %s\n' "$checksum" "$cache/$filename.part" | sha512sum --check -
        mv "$cache/$filename.part" "$cache/$filename"
    else
        printf '%s  %s\n' "$checksum" "$cache/$filename" | sha512sum --check -
    fi
done < "$manifest"
