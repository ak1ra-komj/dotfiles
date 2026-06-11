# Show available recipes
default:
    @just --list --unsorted

# Lint and format python source code
lint:
    ruff check --fix dotpy/
    ruff format dotpy/

# exec shfmt on all shell script
shfmt:
    shfmt -f . | xargs shfmt -w -i=4 -ci

# exec shellcheck on all shell script
shellcheck:
    shfmt -f . | xargs shellcheck

# find broken links
find-broken-links:
    find ~/bin -xtype l
    find ~/.config -xtype l

# unlink broken links
unlink-broken-links:
    find ~/bin -xtype l -exec unlink "{}" \;
    find ~/.config -xtype l -exec unlink "{}" \;

# Remove build artifacts
clean:
    rm -rf dist/ site/ .cache/ .ruff_cache/ .pytest_cache/ htmlcov/ .coverage
    find dotpy/ -type f -name "*.pyc" -delete
    find dotpy/ -type d -name "__pycache__" -delete
