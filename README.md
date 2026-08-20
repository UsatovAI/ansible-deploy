# ansible-deploy

Ansible control repo for autodeploying [`claude-web-console`](https://github.com/UsatovAI/claude-web-console)
and a Claude Code CLI/skills/MCP setup to VPS targets.

This VPS is both the ansible control node (this repo, checked out at `/root/ansible-deploy`) and,
for one of the two inventory groups below, production itself.

## Targets

`inventory/hosts.ini` has two separate groups — they are never meant to be conflated:

- `claude_vps` — a throwaway VPS used only to validate the pipeline end to end.
  `playbook.yml` and `console_deploy.yml` target this group.
- `claudeweb_prod` (`127.0.0.1`, local connection) — this box, the real production
  claudeweb console. Only `claudeweb_console.yml` targets this group.

## Entry points

| Command | Playbook | Target | Does |
|---|---|---|---|
| `make deploy` / `deploy-claude` / `deploy-skills` | `playbook.yml` | `claude_vps` | Installs Claude Code CLI, skills, MCPs |
| `make deploy-site` | `console_deploy.yml` | `claude_vps` | Original claude-web-console bootstrap (pipeline validation only) |
| `make claudeweb-full` / `claudeweb-env` | `claudeweb_console.yml` | `claudeweb_prod` | The only sanctioned way to touch the live console: full redeploy or partial `.env` credential sync |

## Secrets

`group_vars/secrets.yml` (ansible-vault encrypted) and `.vault_pass` (the vault decryption key)
are excluded via `.gitignore` and were never committed to this repo. `group_vars/secrets.yml.example`
documents the full schema with blank placeholder values — copy it, fill it in, then run
`make secrets` to encrypt it into `group_vars/secrets.yml`.

## Note on `roles/skills_mcp/files/skills/code-review-skill/`

The `skills_mcp` role deploys a local, on-disk copy of a third-party skill package
(originally cloned from [`awesome-skills/code-review-skill`](https://github.com/awesome-skills/code-review-skill))
to target VPSes. That subtree is intentionally **not mirrored into this repo** — it's an
unmodified copy of an already-public repo, so duplicating it here would just be dead weight.
If you're standing this pipeline up elsewhere, clone that upstream repo into
`roles/skills_mcp/files/skills/code-review-skill/` yourself before running `deploy-skills`.
