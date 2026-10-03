#!/usr/bin/env bash
# Print lowercase SHA-256 hex of the authenticated leaf SubjectPublicKeyInfo DER.
# Used by SDK build scripts to bake TSERVER_TLS_SPKI_PIN.
set -Eeuo pipefail

HOST="${1:-proxy.huutien.store}"
PORT="${2:-443}"

[[ "$HOST" =~ ^[A-Za-z0-9.-]+$ ]] || exit 1
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] || exit 1
(( PORT >= 1 && PORT <= 65535 )) || exit 1
command -v openssl >/dev/null 2>&1 || exit 1

transcript="$(mktemp "${TMPDIR:-/tmp}/tserver-tls-spki.XXXXXXXX")"
trap 'rm -f -- "$transcript"' EXIT

openssl s_client \
  -connect "${HOST}:${PORT}" \
  -servername "$HOST" \
  -verify_hostname "$HOST" \
  -verify_return_error \
  -showcerts < /dev/null >"$transcript" 2>/dev/null
grep -q 'Verify return code: 0 (ok)' "$transcript"

hex="$(
  openssl x509 -pubkey -noout <"$transcript" 2>/dev/null \
    | openssl pkey -pubin -outform der 2>/dev/null \
    | openssl dgst -sha256 -hex 2>/dev/null \
    | awk '{print $NF}' \
    | tr -d ' \r\n' \
    | tr 'A-F' 'a-f'
)"

[[ "$hex" =~ ^[0-9a-f]{64}$ ]] || exit 1
printf '%s' "$hex"
