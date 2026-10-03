#!/usr/bin/env bash
# Download every tool pinned in ci/tools.lock into $CI_BIN, verifying each
# artifact's SHA-256 before extracting it. Linux amd64 only.
set -euo pipefail
cd "$(dirname "$0")/.."
CI_BIN=${CI_BIN:-$PWD/.ci-bin}
dl=$(mktemp -d); trap 'rm -rf "$dl"' EXIT
mkdir -p "$CI_BIN"
while read -r name url sha; do
  case "$name" in ''|'#'*) continue ;; esac
  f="$dl/$(basename "$url")"
  curl -fsSL --retry 3 -o "$f" "$url"
  got=$(sha256sum "$f" | cut -d' ' -f1)
  if [ "$got" != "$sha" ]; then echo "checksum mismatch for $name: expected $sha, got $got" >&2; exit 1; fi
  case "$f" in
    *.zip)    python3 -m zipfile -e "$f" "$dl/$name.x" && install -m 0755 "$dl/$name.x/$name" "$CI_BIN/$name" ;;
    *.tar.gz) mkdir -p "$dl/$name.x" && tar -xzf "$f" -C "$dl/$name.x" && install -m 0755 "$(find "$dl/$name.x" -type f -name "$name" | head -1)" "$CI_BIN/$name" ;;
    *.py)     install -m 0644 "$f" "$CI_BIN/$name.py" ;;
    *)        install -m 0755 "$f" "$CI_BIN/$name" ;;
  esac
  echo "ok $name ${sha:0:12}"
done < ci/tools.lock
. ci/versions.env
python3 -m venv "$CI_BIN/venv"
"$CI_BIN/venv/bin/pip" install --quiet --disable-pip-version-check "pyyaml==$PYYAML_VERSION"
echo "ok pyyaml $PYYAML_VERSION"
