# ansible
BINDIR ?= $(HOME)/.local/bin
ANSIBLE_PLAYBOOK ?= $(BINDIR)/ansible-playbook

# ansible-playbook
PLAYBOOK_HOSTS ?= localhost
PLAYBOOK_ARGS ?= --inventory=ansible/.ansible/inventory

# GNU Stow
stow_dir ?= $(HOME)/.dotfiles
stow_target ?= $(HOME)

.DEFAULT_GOAL=help
.PHONY: help
help:  ## show this help message
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-10s\033[0m %s\n", $$1, substr($$0, index($$0,$$3)) \
	}' $(MAKEFILE_LIST)

.PHONY: pipx
pipx:
	command -v pipx >/dev/null || { \
		sudo apt-get update -y && \
		sudo apt-get install -y pipx; \
	}

.PHONY: ansible
ansible: pipx  ## pipx install ansible
	command -v ansible >/dev/null || { \
		pipx install ansible && \
		ln -sf $(HOME)/.local/pipx/venvs/ansible/bin/ansible* $(HOME)/.local/bin/; \
	}

.PHONY: install
install: ansible  ## install basic stow packages with ansible and stow
	$(ANSIBLE_PLAYBOOK) playbook.yaml $(PLAYBOOK_ARGS) \
		-e 'playbook_hosts=$(PLAYBOOK_HOSTS)' \
		-e 'stow_dir=$(stow_dir)' -e 'stow_target=$(stow_target)'
