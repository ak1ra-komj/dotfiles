.DEFAULT_GOAL=help
.PHONY: help
help:  ## show this help message
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-20s\033[0m %s\n", $$1, substr($$0, index($$0,$$3)) \
	}' $(MAKEFILE_LIST)

.PHONY: shfmt
shfmt:  ## execute shfmt on all shell script
	shfmt -f . | xargs shfmt -w -i=4 -ci

.PHONY: shellcheck
shellcheck:  ## execute shellcheck on all shell script
	shfmt -f . | xargs shellcheck

.PHONY: agents-skills
agents-skills:  ## install agents-skills
	test -d ~/.agents/skills || mkdir -p ~/.agents/skills
	stow -R -t ~/.agents .agents
