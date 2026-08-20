#!/usr/bin/env bash
# Encrypts group_vars/secrets.yml.example -> group_vars/secrets.yml (ansible-vault),
# then resets the example file back to a blank template.
set -euo pipefail

cd "$(dirname "$0")/.."

EXAMPLE="group_vars/secrets.yml.example"
TEMPLATE="group_vars/secrets.yml.template"
TARGET="group_vars/secrets.yml"
VAULT_PASS_FILE=".vault_pass"

if [[ ! -f "$EXAMPLE" ]]; then
  echo "Missing $EXAMPLE" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Missing $TEMPLATE (canonical blank schema -- needed to reset $EXAMPLE after encrypting)" >&2
  exit 1
fi

if grep -qE '^\s*[a-z_]+:\s*""\s*(#.*)?$' "$EXAMPLE"; then
  echo "Refusing to encrypt: $EXAMPLE still has empty (\"\") values. Fill them in first." >&2
  exit 1
fi

if [[ ! -f "$VAULT_PASS_FILE" ]]; then
  openssl rand -base64 32 > "$VAULT_PASS_FILE"
  chmod 600 "$VAULT_PASS_FILE"
  echo "Generated new vault password at $VAULT_PASS_FILE (keep this, you need it to decrypt/edit later)."
fi

cp "$EXAMPLE" "$TARGET"
ansible-vault encrypt "$TARGET" --vault-password-file "$VAULT_PASS_FILE"
chmod 600 "$TARGET"
echo "Encrypted secrets written to $TARGET"

cp "$TEMPLATE" "$EXAMPLE"
echo "Reset $EXAMPLE to blank template (from $TEMPLATE)."
