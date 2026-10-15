#!/usr/bin/env bash
# Run by mix ec100.release inside the existing Nerves build container, after a build.
set -euo pipefail

cd /workspace/build
system=/workspace/nerves_system_ec100
toolchain=host/opt/ext-toolchain
name="nerves_system_ec100-portable-${NERVES_ARTIFACT_VERSION}-${NERVES_ARTIFACT_SOURCE_FINGERPRINT}"
sources="nerves_system_ec100-sources-${NERVES_ARTIFACT_VERSION}-${NERVES_ARTIFACT_SOURCE_FINGERPRINT}"

# The supplemental source list is specific to the external toolchain in this system.
test "$(< "$toolchain/nerves-toolchain.tag")" = 15.3.0
make legal-info

supplement=legal-info/host-sources/toolchain-external-custom
mkdir -p "$supplement" legal-info/licenses/toolchain-external-custom legal-info/licenses/nerves_system_ec100
cp -a "$toolchain/share/licenses/." legal-info/licenses/toolchain-external-custom/
cp "$toolchain/ct-ng.config" "$toolchain/ct-ng.defconfig" "$supplement/"
cp "$system/LICENSE" legal-info/licenses/nerves_system_ec100/
cp "$system/SOURCES.md" legal-info/EC100-SOURCES.md
cp "$system/release/toolchain-sources.sha512" "$supplement/"

cache=/workspace/dl/ec100-toolchain-sources
bash "$system/release/download-sources.sh" "$cache"
while read -r checksum url; do
    [[ -z "$checksum" || "$checksum" == \#* ]] && continue
    cp "$cache/${url##*/}" "$supplement/"
done < "$system/release/toolchain-sources.sha512"

# Nerves includes notices but omits legal-info/{sources,host-sources} in the binary.
make system NERVES_ARTIFACT_NAME="$name"
mkdir -p "$NERVES_ARTIFACT_DIR"
cp "$name.tar.gz" "$NERVES_ARTIFACT_DIR/"
cp "$name.tar.gz" /dist/

# Include Buildroot itself and the exact system recipes alongside collected sources.
# Exclude only Buildroot's absolute convenience symlink, not its expanded sources.
tar -czf "/dist/$sources.tar.gz.part" \
    --exclude=nerves_system_br/buildroot \
    -C /workspace build/legal-info nerves_system_ec100 nerves_system_br
mv "/dist/$sources.tar.gz.part" "/dist/$sources.tar.gz"

cd /dist
for archive in "$name.tar.gz" "$sources.tar.gz"; do
    if (( $(stat -c %s "$archive") >= 2147483648 )); then
        echo "$archive exceeds GitHub's 2 GiB limit" >&2
        exit 1
    fi
done
sha256sum "$name.tar.gz" "$sources.tar.gz" > SHA256SUMS
