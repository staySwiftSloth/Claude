#!/usr/bin/env bash
# Download offline installers into oem/installers/ and record their SHA-256.
# harden.ps1 refuses any installer whose hash isn't in SHA256SUMS.
#
# The VMs can't download these themselves: their only way out is the egress
# proxy allowlist, so installers are fetched here on the host and copied in.
#
# Pin exact versions. Fill in the URLs you want, then run:  ./fetch-installers.sh
set -euo pipefail
cd "$(dirname "$0")/oem/installers"

# file name (must match selection.json)      URL
declare -A URLS=(
  [vc_redist.x64.exe]="https://aka.ms/vs/17/release/vc_redist.x64.exe"
  # [PowerShell-x64.msi]="https://github.com/PowerShell/PowerShell/releases/download/vX.Y.Z/PowerShell-X.Y.Z-win-x64.msi"
  # [Git-64-bit.exe]="https://github.com/git-for-windows/git/releases/download/vX.Y.Z.windows.1/Git-X.Y.Z-64-bit.exe"
  # [node-x64.msi]="https://nodejs.org/dist/vXX.Y.Z/node-vXX.Y.Z-x64.msi"
  # [7z-x64.exe]="https://www.7-zip.org/a/7zXXXX-x64.exe"
)

for f in "${!URLS[@]}"; do
  echo "fetching $f"
  curl -fL --retry 3 -o "$f.part" "${URLS[$f]}"
  mv "$f.part" "$f"
done

# Record hashes for everything present. Review this file: it is what the VMs trust.
sha256sum -- *.exe *.msi 2>/dev/null > SHA256SUMS || true
cat SHA256SUMS
echo
echo "Compare these against the publisher's published checksums where they offer them"
echo "(PowerShell, Node and Git all publish SHA-256 on their release pages)."
