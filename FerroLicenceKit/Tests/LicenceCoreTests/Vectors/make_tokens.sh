#!/usr/bin/env bash
# Produce licence tokens with GnuPG for the Swift checker's test vectors.
set -euo pipefail
out="$1"; mkdir -p "$out/tokens" "$out/anchors"
H=$(mktemp -d /tmp/flv.XXXXXX); chmod 700 "$H"
g() { gpg --homedir "$H" --batch --yes --pinentry-mode loopback --passphrase "" "$@"; }
fpr() { g --with-colons --list-keys "=$1" | awk -F: '$1=="fpr"{print $10; exit}'; }
g --quick-generate-key "Vector A <a@example.invalid>" ed25519 sign never
g --quick-generate-key "Vector B <b@example.invalid>" ed25519 sign never
g --quick-generate-key "Vector U <u@example.invalid>" ed25519 sign never
g --quick-generate-key "Vector C <c@example.invalid>" ed25519 cert never
A=$(fpr "Vector A <a@example.invalid>"); B=$(fpr "Vector B <b@example.invalid>"); U=$(fpr "Vector U <u@example.invalid>"); C=$(fpr "Vector C <c@example.invalid>")
g --quick-add-key "$C" ed25519 sign never
for k in A B C; do eval f=\$$k; g --armor --export "$f" > "$out/anchors/$k.asc"; done
lic() { printf '{\n  "licence_id": "%s",\n  "licensee": "%s",\n  "issued": "2026-10-24",\n  "not_before": "2026-11-01",\n  "not_after": "2027-10-31",\n  "use": "commercial"%s\n}\n' "$1" "$2" "${3:-}"; }
tok() { # name signer-fpr json-file [extra gpg args]
  local name=$1 who=$2 json=$3; shift 3
  g --armor --clearsign --digest-algo SHA512 "$@" < "$json" > "$H/signed"
  { sed -e '$a\' "$H/signed"; g --armor --export "$who"; } > "$out/tokens/$name.asc"
}
lic 019a1171-8f20-7b3e-a5c4-2e9d7f60b1a8 "Example Hospital NV" > "$H/l1"
lic 019a1171-8f20-7b3e-a5c4-2e9d7f60b1a9 'Ünïcode \"Quoted\" / Slash & Co. — ✓' > "$H/l2"
lic 019a1171-8f20-7b3e-a5c4-2e9d7f60b1aa "Seats Corp" ',
  "seats": 5' > "$H/l3"
sed 's/2027-10-31/2027-13-01/' "$H/l1" > "$H/l4"
tok ok_a "$A" "$H/l1" --local-user "$A!"
tok ok_b_unicode "$B" "$H/l2" --local-user "$B!"
tok untrusted "$U" "$H/l1" --local-user "$U!"
tok subkey_signed "$C" "$H/l1" --local-user "$(g --with-colons --list-keys "$C" | awk -F: '$1=="fpr"{n++} n==2{print $10; exit}')!"
tok two_signatures "$A" "$H/l1" --local-user "$A!" --local-user "$B!"
tok unknown_field "$A" "$H/l3" --local-user "$A!"
tok bad_date "$A" "$H/l4" --local-user "$A!"
sed 's/Example Hospital NV/Example Hospital BV/' "$out/tokens/ok_a.asc" > "$out/tokens/tampered.asc"
# a binary (non-text) signature in a cleartext frame
g --armor --detach-sign --digest-algo SHA512 --local-user "$A!" < <(printf '%s' "$(cat "$H/l1")") > "$H/bin.sig"
{ printf -- '-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n'; cat "$H/l1"; cat "$H/bin.sig"; g --armor --export "$A"; } > "$out/tokens/binary_signature.asc"
sed '/-----BEGIN PGP PUBLIC KEY BLOCK-----/,$d' "$out/tokens/ok_a.asc" > "$out/tokens/no_certificate.asc"
cp "$H/l1" "$out/l1.json"; cp "$H/l2" "$out/l2.json"
gpgconf --homedir "$H" --kill gpg-agent || true
echo "A=$A B=$B U=$U C=$C"
