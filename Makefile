.PHONY: secrets deploy deploy-claude deploy-skills deploy-site deploy-resume-page edit-secrets claudeweb-full claudeweb-env

secrets:
	./scripts/load_secrets.sh

edit-secrets:
	ansible-vault edit group_vars/secrets.yml --vault-password-file .vault_pass

deploy:
	ansible-playbook playbook.yml --vault-password-file .vault_pass

deploy-claude:
	ansible-playbook playbook.yml --tags claude --vault-password-file .vault_pass

deploy-skills:
	ansible-playbook playbook.yml --tags skills --vault-password-file .vault_pass

# The claude-web-console app (/root/site -> /opt/claude-web-console on the
# VPS) -- this is "the site" the AGENT-32 epic actually means.
deploy-site:
	ansible-playbook console_deploy.yml --vault-password-file .vault_pass

# Not part of the epic -- kept only because it's already live on the VPS
# from an earlier misunderstanding of what "site" referred to.
deploy-resume-page:
	ansible-playbook playbook.yml --tags site --vault-password-file .vault_pass

# The claudeweb console actually already running on THIS box (prod), as
# opposed to deploy-site above (the throwaway test-VPS target from
# inventory's claude_vps group). Both go through scripts/claudeweb.sh --
# the single method for touching claudeweb's deployed state, whether it's
# a full redeploy or a partial .env update. See AGENT-7's "Claudeweb skill
# to repair, config" and the deploy-claude-console skill.
claudeweb-full:
	./scripts/claudeweb.sh full

# Usage: make claudeweb-env ARGS="KEY=VALUE KEY2=VALUE2"
# Also reports claudeweb's Claude Code login health (metadata only) and
# prints the setup-token fix command if it looks stale -- part of the same
# "sync claudeweb's credentials" command, not a separate target.
claudeweb-env:
	./scripts/claudeweb.sh env $(ARGS)
