## `python3-argcomplete` for ansible

### Let's start from `pipx`

之前在安装 `pipx` 的时候第一次见到 `python3-argcomplete` package,

```ShellSession
$ apt info pipx | grep '^Depends:'

Depends: python3-venv, python3-argcomplete, python3-importlib-metadata | python3 (>> 3.8), python3-packaging, python3-userpath, python3:any
```

我们可以看到 `pipx` 依赖 `python3-argcomplete` package.

当时为 pipx 配置 argcomplete 时选择的是在 dotfiles 的 `~/.bashrc` 中新增如下行,

```
command -v pipx >/dev/null && eval "$(register-python-argcomplete pipx)"
```

刚刚在看 [Adding Ansible command shell completion](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#adding-ansible-command-shell-completion) 也看到了 argcomplete.

### 那么, argcomplete 是什么?

[argcomplete](https://kislyuk.github.io/argcomplete/) 的文档提到,

> Argcomplete provides easy, extensible command line tab completion of arguments for your Python application.

> It makes two assumptions:

> - You’re using bash or zsh as your shell
> - You’re using [argparse](http://docs.python.org/3/library/argparse.html) to manage your command line arguments/options

需要在 .py 文件开头添加一行 `PYTHON_ARGCOMPLETE_OK` 的注释作为标记,

> Add the `PYTHON_ARGCOMPLETE_OK` marker and a call to `argcomplete.autocomplete()` to your Python application as follows:

需要在执行 `parser.parse_args()` 之前先执行 `argcomplete.autocomplete(parser)`,

> It must be called **after** ArgumentParser construction is complete, but **before** the `ArgumentParser.parse_args()` method is called.

文档中提到一些"副作用", 它会在用户每次按下 TAB 键时执行一遍你的程序, 因此你在开发命令行工具时应避免执行到 `argcomplete.autocomplete(parser)` 之前产生什么"副作用",

> [!warning] Argcomplete gets completions by running your program. It intercepts the execution flow at the moment `argcomplete.autocomplete()` is called. After sending completions, it exits using `exit_method` (`os._exit` by default). This means if your program has any side effects that happen before `argcomplete` is called, those side effects will happen every time the user presses `<TAB>` (although anything your program prints to stdout or stderr will be suppressed). For this reason it’s best to construct the argument parser and call `argcomplete.autocomplete()` as early as possible in your execution flow.

也需要避免将耗时比较长的操作放在它前面而发生性能问题,

> [!warning] If the program takes a long time to get to the point where `argcomplete.autocomplete()` is called, the tab completion process will feel sluggish, and the user may lose confidence in it. So it’s also important to minimize the startup time of the program up to that point (for example, by deferring initialization or importing of large modules until after parsing options).

### ansible 官方文档是如何配置 argcomplete 的?

我们的 ansible 本身是通过 pipx 安装的, ansible 官方文档提到在执行 `pipx inject ansible argcomplete` 推荐带上 `--include-apps` 选项, 即,

```
pipx inject --include-apps ansible argcomplete
```

而 `pipx inject --include-apps` 选项的行为是 "Add apps from the injected packages onto your PATH", 因为我们在安装 `pipx` 时已经安装 `python3-argcomplete` package, 相关可执行文件已经位于 `/usr/bin` 目录中, 因此我们尝试这么执行时会报出下面的警告,

```ShellSession
$ pipx inject --include-apps ansible argcomplete
⚠️  Note: activate-global-python-argcomplete was already on your PATH at /usr/bin/activate-global-python-argcomplete
⚠️  Note: python-argcomplete-check-easy-install-script was already on your PATH at /usr/bin/python-argcomplete-check-easy-install-script
⚠️  Note: register-python-argcomplete was already on your PATH at /usr/bin/register-python-argcomplete
```

这种情况下会"污染"我们的 PATH, 虽然这种"冲突"并不会有太大的问题, 因此我们并不需要 `--include-apps` 选项, 即,

```
pipx inject ansible argcomplete
```

那么 inject 这个步骤是必要的吗? 答案是必要的.

简单翻一下 ansible 的 source code, 我们可以发现下面的段落,

```python
# https://github.com/ansible/ansible/blob/cae4f90b21bc40c88a00e712d28531ab0261f759/lib/ansible/cli/__init__.py#L111-L115
try:
    import argcomplete
    HAS_ARGCOMPLETE = True
except ImportError:
    HAS_ARGCOMPLETE = False
```

```python
# https://github.com/ansible/ansible/blob/cae4f90b21bc40c88a00e712d28531ab0261f759/lib/ansible/cli/__init__.py#L448-L449
if HAS_ARGCOMPLETE:
    argcomplete.autocomplete(self.parser)
```

ansible 需要能 `import argcomplete` 才能实现 命令行补齐, pipx 的 venv 环境如果没有安装 argcomplete, 那么在 `import argcomplete` 这一步失败时会将 `HAS_ARGCOMPLETE` 标记为 `False`, 因此也就没法继续补齐.

### 如何继续配置 argcomplete

[Adding Ansible command shell completion](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#adding-ansible-command-shell-completion) 文档中提到,

> There are 2 ways to configure `argcomplete` to allow shell completion of the Ansible command line utilities: globally or per command.

我们暂不考虑 per command configuration, 对于下面这条指令,

```ShellSession
$ activate-global-python-argcomplete --user
Installing bash completion script ~/.bash_completion.d/python-argcomplete
```

> This will write a bash completion file to a user location. Use `--dest` to change the location or `sudo` to set up the completion globally.

在我的环境中, `~/.bashrc` 并没有导入 `~/.bash_completion.d` 的行为 (可能被我 dotfiles 中的 `~/.bashrc` 精简掉了), 考虑已安装 pipx 且是通过 apt repo 安装的, 我们可以直接使用全局配置方式, 这条命令应该只需要执行一次 (感觉可以放到 `pipx` 的 `control/postinst` 中?),

```ShellSession
$ sudo activate-global-python-argcomplete
Installing bash completion script /etc/bash_completion.d/python-argcomplete
```

可以先用一段时间, 如果足够好用的话, 以后在开发比较复杂的命令行程序时, 也可以在以后的开发流程中加入这个步骤.
