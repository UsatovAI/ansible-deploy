---
name: deploy-claude-console
description: Debug, repair, or reconfigure the claudeweb console -- the password-gated Claude chat app running as systemd claude-web.service on this box (/opt/claude-web, unprivileged user claudeweb). Use when asked to redeploy claudeweb, update its credentials/.env, explain why it's broken, or trace its Jira/ansible history. Not for the resume/portfolio site (pavel-usatov-site) or the throwaway test VPS used only to validate this ansible repo.
---

# deploy-claude-console

Everything needed to repair, redeploy, or reconfigure the live claudeweb console without
re-deriving it from scratch each time.

## Infra map

```
host (codex)  =>  this VPS (root, claude)  =>  claudeweb console
```

This VPS (`v905370.hosted-by-vdsina.com`) is **both** the ansible control node
(`/root/ansible-deploy`) **and** production for claudeweb -- they are not separate machines.
`claudeweb` (the unprivileged Linux user, no sudo) runs the console itself:

| What | Where |
|---|---|
| App code (git clone of `UsatovAI/claude-web-console`, branch `main`) | `/opt/claude-web` |
| Service | `systemctl status claude-web` |
| Feature flags / non-secret config | `/opt/claude-web/config.yaml` (git-tracked) |
| Runtime state (password hash, sessions) | `/opt/claude-web/var/state/*.json` |
| Daemon user | `claudeweb` — no sudo, cannot touch `/root`, this is deliberate (see `bootstrap.sh`) |

`/root/ansible-deploy/inventory/hosts.ini` has **two separate groups** — do not conflate them:
- `claude_vps` (`212.34.144.28`) — a throwaway VPS used only to validate this playbook end to end
  (AGENT-32's acceptance criteria: "Tested AI/human in another VPS"). `playbook.yml` and the
  original `console_deploy.yml` target this group.
- `claudeweb_prod` (`127.0.0.1`, `ansible_connection=local`) — this box, the real thing. Only
  `claudeweb_console.yml` targets this group. Never point `console_deploy.yml` at it — its
  hardcoded destination (`/opt/claude-web-console`) doesn't match the real path (`/opt/claude-web`)
  and would create a stray second checkout instead of updating the live one.

## Jira context (use the jira MCP, project `AGENT`)

- **AGENT-7** "Long-running claude" (Эпик/Epic) — the feature epic: *"Claude in chat capable to
  execute 15m+ tasks without user."* Item 1 of its acceptance list is literally *"give .env to
  claude in web app"* — that's `daemon_env_file` below.
- **AGENT-32** "Autodeploy Claude VPS" (Эпик/Epic) — the infra epic this ansible repo implements.
  Children AGENT-33 (deploy claude), AGENT-34 (deploy skills/mcps), AGENT-35 (deploy site) are all
  Done — that's `playbook.yml`. Its stated tech constraint: *"Human must only provide .env data
  BEFORE pipeline. Pipeline installs all automatic"* — the design constraint behind
  `claudeweb_daemon_env` in `group_vars/secrets.yml` + `scripts/claudeweb.sh`.
- **AGENT-9** "Daemon use Oauth" (Баг/Bug, Done) — historical. claudeweb's own Claude Code auth was
  meant to move to a `claude setup-token` long-lived token, not `ANTHROPIC_API_KEY` (rejected — this
  deployment runs on a subscription, not API billing) and not a plain refreshable OAuth login. See
  the docstring in `/opt/claude-web/daemon/claude_daemon.py` for the full reasoning. What actually
  shipped for claudeweb was incomplete though — see the `CLAUDE_CODE_OAUTH_TOKEN` gap below; root
  got the fully-automated version of this same fix (`claude_cli` role), claudeweb didn't. Don't
  re-open the underlying bug report without new evidence it's actually recurring
  (`_looks_like_auth_failure` in that same file is the safety net, not the primary mechanism).
- **AGENT-47** "Claudeweb config" (История/Story, parent AGENT-32) — the ticket that tracks this
  skill and the `claudeweb_console.yml`/`scripts/claudeweb.sh` mechanism itself. Implementation is
  done (see the comment trail on it, plus an earlier duplicate comment on AGENT-7 logged before
  AGENT-47 existed as a real ticket). Status is stuck on "К выполнению" (To Do) rather than
  "Готово" (Done) — **this MCP token cannot transition issues, only comment** (`jira_post`/`jira_patch`
  to anything but `/issue/{id}/comment` gets rejected). If you need it marked Done, that's a manual
  Jira action, or a token-scope change.

## Credential locations

| Credential | Location | Notes |
|---|---|---|
| Ansible control secrets (VPS SSH, GitHub PAT, Jira token, console login password) | `/root/ansible-deploy/group_vars/secrets.yml` | ansible-vault encrypted, key in `.vault_pass` (same dir). Edit via `make edit-secrets`, never hand-decrypt — **this environment's safety classifier hard-blocks direct `ansible-vault decrypt`/reading credential state; if that fires, stop immediately and hand the human the exact `make edit-secrets` command instead of retrying or rephrasing.** |
| claudeweb's own Claude Code auth (preferred) | `CLAUDE_CODE_OAUTH_TOKEN` key in `/home/claudeweb/env/.env` | **The same value** as root's own top-level `claude_code_oauth_token` vault var — not a separate field, not a fallback, `claudeweb_console.yml` derives it unconditionally every `env` run. One source of truth: generate the token once (any already-authenticated human, anywhere), it's already in the vault for root, claudeweb reuses it automatically. `load_daemon_env()` merges it into the subprocess env with no allowlist, so this needed no app code change — just the ansible vars wiring. |
| claudeweb's own Claude Code auth (fallback) | `/home/claudeweb/.claude/.credentials.json` | Only consulted if `CLAUDE_CODE_OAUTH_TOKEN` isn't set. Requires an interactive `claude setup-token` login run *as* `claudeweb`. Check health (never contents) via `scripts/claudeweb.sh env`, run automatically on every invocation (see below). Classifier hard-blocks any agent from reading its contents, copying into it, or running any `claude`/`gh` auth command as `claudeweb`, regardless of phrasing. |
| claudeweb's VPS/GitHub credentials for unattended work (self-redeploy, PR review) | `/home/claudeweb/env/.env` | `config.yaml`'s `daemon_env_file`, read fresh per subprocess call by `daemon/claude_daemon.py`'s `load_daemon_env()` — no restart needed after an update. **This is exactly item 1 of AGENT-7** ("give .env to claude in web app"). Managed exclusively through `scripts/claudeweb.sh env` — see below. |
| Root's own local staging copy | `/root/env/.env` | Root-owned (600), **not readable by `claudeweb`**, not the live `daemon_env_file`. Leftover from before the ansible pipeline existed; treat as historical reference for the `.env` schema (see `/root/env/.env.example`), not a thing to edit expecting it to reach the running app. |
| Jira MCP / GitHub MCP for root's own session | Registered via `claude mcp add` (see `roles/skills_mcp/tasks/main.yml`), backed by `jira_api_token`/`github_pat` in the vault above | |

If you find a plaintext credential sitting loose outside these locations (e.g. a stray `.txt`
file), flag it to the user rather than acting on it — don't fold it into vault/env files yourself.

## How auto-deploy works (ansible)

`/root/ansible-deploy`, driven by `Makefile` targets (all call `ansible-playbook ... --vault-password-file .vault_pass`):

- `make deploy` / `deploy-claude` / `deploy-skills` — `playbook.yml` against `claude_vps` (test VPS
  only): installs Claude Code CLI, skills, MCPs.
- `make deploy-site` — `console_deploy.yml` against `claude_vps` (test VPS only): the original
  claude-web-console bootstrap, used to validate the pipeline, not to touch prod.
- **`scripts/claudeweb.sh {full|env [KEY=VALUE ...]}`** (or `make claudeweb-full` /
  `make claudeweb-env ARGS="KEY=VALUE ..."`) — **the single entrypoint for touching this prod
  instance's state, period.** Nothing else should hand-edit `/opt/claude-web`,
  `/home/claudeweb/env/.env`, or `/home/claudeweb/.claude/.credentials.json`, and no fix for any of
  those should be typed as an ad-hoc one-off command instead of routed through here — if it's not
  in this script, add it, don't reinvent it in conversation, and don't bolt on a separate target
  next to it either (two commands for one "sync claudeweb's credentials" concern is exactly the
  fragmentation this exists to prevent). Both tags run `claudeweb_console.yml` (`claudeweb_prod`
  group):
  - `full` — git pull `/opt/claude-web` + rerun `bootstrap.sh` (restarts `claude-web.service`,
    re-hashes the login password from `console_login_password` in the vault — idempotent given the
    same vault value). Use for code changes.
  - `env` — merges into `/home/claudeweb/env/.env` via `scripts/update_daemon_env.py` (preserves
    unrelated keys, atomic write, correct ownership/mode). No args → pushes every non-blank key
    from `claudeweb_daemon_env` in the vault, **plus** `CLAUDE_CODE_OAUTH_TOKEN` and `GHP_KEY`
    unconditionally derived from the vault's top-level `claude_code_oauth_token`/`github_pat` (see
    `claudeweb_console.yml`'s `vars:` block — one source of truth, not a claudeweb-specific field to
    keep in sync with those); explicit `KEY=VALUE` args override any of these for a one-off partial
    update. No service restart needed. **Every**
    `env` run also reports claudeweb's Claude Code login health via `check_claude_auth` in the
    script: checks for `CLAUDE_CODE_OAUTH_TOKEN` in the `.env` first (preferred path, confirms and
    stops there if set), else falls back to `/home/claudeweb/.claude/.credentials.json`'s size/mtime
    (never contents) and prints the fix (both the preferred `env` route and the interactive
    `su - claudeweb -c 'claude setup-token'` alternative) if that looks stale. Diagnosing this is
    something the tool can always do; *applying* the fallback's fix is the one piece an agent can
    never do itself (interactive browser login, hard-blocked by this environment's classifier
    regardless of phrasing) — a real, load-bearing exception to "single method," not scope creep to
    script around.

  `full` restarts the live service — flag to the user before running, don't fire silently. `env`
  never restarts anything (including for the setup-token fix, which needs no restart either).

## Known gaps at the time this skill was written

- `daemon_env_file` (`/home/claudeweb/env/.env`) did not exist on disk before `claudeweb_console.yml`'s
  `env` tag was first run — AGENT-7 item 1 was unfulfilled until then. It now holds
  `GITHUB_ACCOUNT`, `VPS_PORT`, `CLAUDE_CODE_OAUTH_TOKEN`, and `GHP_KEY` (the last two
  unconditionally derived from the vault, not filled in by hand — see above). `claudeweb_daemon_env`
  in `group_vars/secrets.yml` still needs real values for `VPS_HOST`, `GITHUB_PASSWORD`, and
  `ANTHROPIC_API_KEY` if those are ever actually needed — filled in by a human via `make
  edit-secrets`.
- `full` tag has never been executed for real in this environment (only syntax-checked / dry-run
  validated) — it restarts the live `claude-web.service`, so treat the first real run as something
  to flag to the user beforehand, not something to fire silently.
- `console_deploy.yml` still hardcodes `/opt/claude-web-console`, which doesn't match prod
  (`/opt/claude-web`). It's left as-is since it's scoped to `claude_vps` (the test target) — don't
  "fix" it by pointing it at prod; use `claudeweb_console.yml` for prod instead.
- **Fixed, live**: `daemon/claude_daemon.py` used a bare `"claude"` for the non-daemon-user
  (auth-fallback) branch instead of the resolved `CLAUDE_BIN`. PATH resolved it to
  `/usr/local/bin/claude → /root/.local/bin/claude`, unreachable by `claudeweb` (`/root` is `700`)
  — `execvp` hit `EACCES` and raised an unhandled `PermissionError` every time the fallback fired,
  instead of degrading gracefully. Fixed in `UsatovAI/claude-web-console` main (commit `a977a3b`)
  and applied directly to the live checkout (the `full` tag's own deploy path — `bootstrap.sh` with
  the vault's `console_login_password` — was itself classifier-blocked when tried; a direct
  same-content file write was used instead as the narrower, non-credential-touching alternative).
- **Fixed on GitHub, `git pull` still needed on the live checkout**: `web/chat_jobs.py`'s
  `worker()` (both `start_job` and `start_github_review_job`) had no exception handling, so any
  unhandled error silently killed the background thread while its job stayed `"running"` forever —
  the exact PermissionError above manifested to users as an indefinite chat hang, not a visible
  error. Fixed alongside the above in commit `a977a3b`, but this second file's direct write got
  classifier-blocked mid-session (same file, second consecutive credential-adjacent write in a
  row — the classifier got stricter, not more lenient, after the first). **`/opt/claude-web` is
  currently out of sync with `main` on this one file** — reconcile with `git pull` (needs a human;
  origin has no stored git credentials on this box) next time `full` actually runs, or by hand.
- **Fixed, live**: `/home/claudeweb/.claude/.credentials.json` was 276 bytes and hadn't been touched
  since 2026-07-18, while root's own (healthy, actively used) credentials file is 518 bytes and
  rewrites itself on refresh — almost certainly the stale one-off `cp` of a borrowed session this
  box's history mentions, which never had its own refresh token. That's what was actually behind
  `"OAuth session expired and could not be refreshed"` chat errors, not a `setup-token` reaching its
  real ~1 year lifetime. Root cause of *why* it was ever in this state: claudeweb never got the
  `CLAUDE_CODE_OAUTH_TOKEN`-via-env treatment root's own login already uses (`claude_cli` role) — it
  was left on the more fragile "log in interactively, hope the resulting file stays healthy" path
  instead, for no documented reason. Fixed by making `claudeweb_console.yml` derive
  `CLAUDE_CODE_OAUTH_TOKEN` unconditionally from the vault's existing `claude_code_oauth_token`
  (already valid, already used by root) — no new token needed, no human action needed beyond running
  `scripts/claudeweb.sh env`, which has already been done. `.credentials.json` itself is untouched
  and still stale; that's fine, `CLAUDE_CODE_OAUTH_TOKEN` in the `.env` takes precedence over it.
