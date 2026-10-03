#!/usr/bin/env bash
# Chay tren Ubuntu/WSL co Theos + iOS SDK
set -euo pipefail

if [[ -z "${THEOS:-}" ]]; then
  if [[ -d "$HOME/theos" ]]; then
    export THEOS="$HOME/theos"
  else
    echo "THEOS chua set. Vi du: export THEOS=~/theos"
    exit 1
  fi
fi

export PATH="$THEOS/bin:$PATH"
cd "$(dirname "$0")"

echo "THEOS=$THEOS"
echo "SDK dir:"; ls "$THEOS/sdks" 2>/dev/null || echo "(trong)"
if [[ -z "${TSERVER_CLIENT_API_KEY:-}" ]]; then
  echo "ERROR: TSERVER_CLIENT_API_KEY is required."
  echo "       Provide it through the approved vendor build flow; this script never reads server/.env."
  exit 1
fi

if [[ ! "$TSERVER_CLIENT_API_KEY" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "ERROR: TSERVER_CLIENT_API_KEY must be a 64-character hexadecimal value."
  exit 1
fi

export TSERVER_CLIENT_API_KEY
echo "Building portable libAPIClient.a for https://proxy.huutien.store ..."
echo "Package token is runtime config; the same .a works on local/VPS builds when CLIENT_API_KEY matches the server."

make clean
make -j1
bash pack_customer_sdk.sh

echo
echo "Done. Customer package:"
echo "  $(cd .. && pwd)/dist/APIClient"
ls -lh ../dist/APIClient/APIClient.h ../dist/APIClient/libAPIClient.a 2>/dev/null || true
