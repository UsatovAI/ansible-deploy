#!/usr/bin/env bash
# Single entrypoint for interacting with the live claudeweb console's state.
# full and env are the only two operations -- nothing else should hand-edit
# /opt/claude-web, /home/claudeweb/env/.env, or
# /home/claudeweb/.claude/.credentials.json directly. `env` covers claudeweb's
# credentials broadly: it merges the VPS/GitHub .env AND reports whether
# claudeweb's own Claude Code login looks healthy, printing the fix command
# if not -- one command for "sync claudeweb's credentials", not a second
# target bolted on next to it.
#
# Usage:
#   scripts/claudeweb.sh full                              # git pull + bootstrap.sh, restarts claude-web.service
#   scripts/claudeweb.sh env                                # push every non-blank secrets.yml claudeweb_daemon_env key + check claude login health
#   scripts/claudeweb.sh env KEY=VALUE [KEY2=VALUE2 ...]     # merge just these keys, no restart, + check claude login health
set -euo pipefail

cd "$(dirname "$0")/.."

VAULT_PASS_FILE=".vault_pass"
PLAYBOOK="claudeweb_console.yml"

check_claude_auth() {
  local env_file="/home/claudeweb/env/.env"
  # /home/claudeweb/env/.env is fair game to read -- it's the daemon's own
  # config file, managed entirely by this script, unlike
  # /home/claudeweb/.claude/.credentials.json below. daemon/claude_daemon.py
  # merges every key here straight into the claude subprocess's env with no
  # allowlist, so a CLAUDE_CODE_OAUTH_TOKEN set here takes effect (and takes
  # precedence over the credentials file) with no app code change needed --
  # this is the preferred, single-method-friendly fix; see the comment next
  # to CLAUDE_CODE_OAUTH_TOKEN in group_vars/secrets.yml.template.
  if [[ -f "$env_file" ]] && grep -qE '^CLAUDE_CODE_OAUTH_TOKEN=.+' "$env_file"; then
    echo "claudeweb Claude Code login: CLAUDE_CODE_OAUTH_TOKEN is set in $env_file (the preferred path) -- this takes precedence over the credentials file below."
    return
  fi

  local cred_file="/home/claudeweb/.claude/.credentials.json"
  if [[ ! -f "$cred_file" ]]; then
    echo "claudeweb Claude Code login: no CLAUDE_CODE_OAUTH_TOKEN in $env_file, and no credentials file at $cred_file -- claudeweb has never logged in."
    print_setup_token_fix
    return
  fi
  local size mtime_h age_days
  size=$(stat -c %s "$cred_file")
  mtime_h=$(stat -c %y "$cred_file")
  age_days=$(( ($(date +%s) - $(stat -c %Y "$cred_file")) / 86400 ))
  echo "claudeweb Claude Code login: no CLAUDE_CODE_OAUTH_TOKEN in $env_file; falling back to $cred_file (${size} bytes, last modified ${mtime_h}, ${age_days}d ago)."
  # Metadata only -- reading this file's *contents* (or root's, for
  # comparison) is off-limits to an agent by design (see the
  # deploy-claude-console skill). Heuristic, not proof: a genuine,
  # independently-authenticated `claude setup-token` login rewrites itself
  # on refresh (compare against root's own .credentials.json, which
  # self-refreshes during active use) and is a full access+refresh token
  # pair, comparably sized to that. Small AND never touched since creation
  # is the exact signature of a stale one-off copy of someone else's
  # session pasted in once, not a real independent login.
  if [[ $size -lt 400 && $age_days -gt 3 ]]; then
    echo "  -> looks stale/incomplete (small + untouched while a healthy token would self-refresh). Needs a real login, not another copy."
    print_setup_token_fix
  else
    echo "  -> looks healthy by this heuristic. Not a guarantee -- only a real chat request actually proves it works."
  fi
}

print_setup_token_fix() {
  cat <<EOF
  Fix -- \`claude setup-token\` output is the credential either way, but
  where it goes matters:

  Preferred: run it as ANY already-authenticated human, anywhere (not
  necessarily as claudeweb, not necessarily on this box), capture the
  printed token, then push it through this same tool:

      $0 env CLAUDE_CODE_OAUTH_TOKEN=<token>

  Alternative: run it interactively as claudeweb directly (writes to
  $cred_file instead) -- must be run by a human, not this tool or any
  agent; this environment hard-blocks any agent from touching claudeweb's
  credential state directly, regardless of phrasing:

      su - claudeweb -c 'claude setup-token'

  Either way, no service restart needed afterward -- credentials are read
  fresh per chat message (see daemon/claude_daemon.py's load path).
EOF
}

mode="${1:-}"
case "$mode" in
  full)
    if [[ ! -f "$VAULT_PASS_FILE" ]]; then
      echo "Missing $VAULT_PASS_FILE -- run 'make secrets' first." >&2
      exit 1
    fi
    ansible-playbook "$PLAYBOOK" --limit claudeweb_prod --tags full --vault-password-file "$VAULT_PASS_FILE"
    ;;
  env)
    if [[ ! -f "$VAULT_PASS_FILE" ]]; then
      echo "Missing $VAULT_PASS_FILE -- run 'make secrets' first." >&2
      exit 1
    fi
    shift
    if [[ $# -eq 0 ]]; then
      # No KEY=VALUE args: push every non-blank key from secrets.yml's
      # claudeweb_daemon_env (the playbook's own default for this tag) --
      # same mechanism as a partial update, just the full configured set.
      ansible-playbook "$PLAYBOOK" --limit claudeweb_prod --tags env --vault-password-file "$VAULT_PASS_FILE"
    else
      # Build the env_updates JSON dict without ever putting secret values on
      # the ansible-playbook command line (they'd land in shell history /
      # process list) -- write it to a gitignored tmp file instead and pass
      # that as an @-loaded extra-vars file.
      tmp_vars="$(mktemp)"
      trap 'rm -f "$tmp_vars"' EXIT
      python3 - "$@" > "$tmp_vars" <<'PY'
import json, sys
updates = {}
for pair in sys.argv[1:]:
    if "=" not in pair:
        sys.exit(f"Bad KEY=VALUE pair: {pair!r}")
    k, _, v = pair.partition("=")
    updates[k] = v
json.dump({"env_updates": updates}, sys.stdout)
PY
      ansible-playbook "$PLAYBOOK" --limit claudeweb_prod --tags env \
        --vault-password-file "$VAULT_PASS_FILE" \
        -e "@$tmp_vars"
    fi
    echo
    check_claude_auth
    ;;
  *)
    echo "Usage: $0 {full|env [KEY=VALUE ...]}" >&2
    exit 1
    ;;
esac
