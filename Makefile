# ansible
BINDIR ?= $(HOME)/.local/bin
ANSIBLE_PLAYBOOK ?= $(BINDIR)/ansible-playbook

# ansible-playbook
playbook_hosts ?= localhost

.DEFAULT_GOAL=help
.PHONY: help
help:  ## show this help message
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-20s\033[0m %s\n", $$1, substr($$0, index($$0,$$3)) \
	}' $(MAKEFILE_LIST)

.PHONY: shfmt
shfmt:  ## execute shfmt on all shell script
	shfmt -f . | \
		xargs shfmt --write --indent=4 --case-indent

.PHONY: shellcheck
shellcheck:  ## execute shellcheck on all shell script
	shfmt -f . | xargs shellcheck

.PHONY: ansible
ansible:  ## install ansible with pipx
	command -v ansible >/dev/null || { \
		pipx install --preinstall argcomplete --include-deps ansible
	}

.PHONY: install
install: ansible  ## install basic stow packages with ansible and stow
	$(ANSIBLE_PLAYBOOK) site.yaml -e 'playbook_hosts=$(playbook_hosts)'
