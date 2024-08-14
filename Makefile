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

.PHONY: jq
jq:
	command -v jq >/dev/null || { \
		sudo apt-get update -y && \
		sudo apt-get install -y jq; \
	}

DIFFT_VERSION ?= x86_64-unknown-linux-gnu
.PHONY: difft
difft: jq  ## install difft from github releases
	command -v difft >/dev/null || { \
		curl -s https://api.github.com/repos/Wilfred/difftastic/releases/latest | \
			jq -r '.assets[].browser_download_url | select(test("$(DIFFT_VERSION)"))' | \
			wget -q -i - && \
		tar -xf difft-$(DIFFT_VERSION).tar.gz && \
		sudo install -m 755 difft /usr/local/bin/difft && \
		rm difft-$(DIFFT_VERSION).tar.gz difft; \
	}

.PHONY: install
install: ansible  ## install basic stow packages with ansible and stow
	$(ANSIBLE_PLAYBOOK) playbook.yaml $(PLAYBOOK_ARGS) \
		-e 'playbook_hosts=$(PLAYBOOK_HOSTS)' \
		-e 'stow_dir=$(stow_dir)' -e 'stow_target=$(stow_target)'
