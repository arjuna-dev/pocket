#!/bin/zsh

set -euo pipefail

identity_name="Pocket Local Development"
existing_identity="$(security find-identity -p codesigning | awk '/"Pocket Local Development"/ { print $2; exit }')"
# Private material exists only in a protected temporary directory until it is
# imported into the user's Keychain. Only codesign is preauthorized to use it.
umask 077
signing_temp_dir="$(mktemp -d "${TMPDIR:-/tmp/}pocket-signing.XXXXXX")"
trap 'rm -rf "$signing_temp_dir"' EXIT
keychain_path="$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
if [[ -n "$existing_identity" ]]; then
    security find-certificate -c "$identity_name" -p "$keychain_path" > "$signing_temp_dir/certificate.pem"
    security add-trusted-cert -r trustRoot -p codeSign -k "$keychain_path" "$signing_temp_dir/certificate.pem"
    echo "Pocket's local signing identity is installed and trusted for code signing."
    exit 0
fi

bundle_password="$(openssl rand -hex 32)"
export POCKET_CERTIFICATE_PASSWORD="$bundle_password"

cat > "$signing_temp_dir/certificate.cnf" <<'EOF'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = Pocket Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$signing_temp_dir/certificate.cnf" \
    -keyout "$signing_temp_dir/private.key" \
    -out "$signing_temp_dir/certificate.pem" 2>/dev/null
openssl pkcs12 -export \
    -inkey "$signing_temp_dir/private.key" \
    -in "$signing_temp_dir/certificate.pem" \
    -name "$identity_name" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout env:POCKET_CERTIFICATE_PASSWORD \
    -out "$signing_temp_dir/identity.p12"
security import "$signing_temp_dir/identity.p12" \
    -k "$keychain_path" -P "$bundle_password" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign \
    -k "$keychain_path" "$signing_temp_dir/certificate.pem"

echo "Installed Pocket's local signing identity. Rebuild with ./Scripts/build_app.sh."
echo "The next WebCrypto Keychain prompt still needs your approval."
