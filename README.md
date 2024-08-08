
# README.md for dotfiles

使用 [GNU Stow](https://www.gnu.org/software/stow/) 管理的 dotfiles (自家用).

## quick start

现在你可以直接执行 `make install` 安装最基本的几个 packages, 参考 Makefile.

## git-config `includeIf`

为避免 个人配置 与 git package 中的配置冲突, 原本的 `~/.gitconfig` 被移动到 `~/.config/git/config`,
现在可以在 `~/.gitconfig` 中加入自定义配置, 比如全局的 `user.name` 和 `user.email` 配置, git 会自行合并不同位置的配置文件.

尝试搜索 "gitconfig based on directory" 发现了 git-config 的 `includeIf` 选项, 这里给出一则配置示例,

假设需要为 `~/code/git.company-a.net` 目录配置不同的 `user.name`, `user.email` 和 ssh key,

```ini
; ~/.gitconfig, git package 的配置 ~/.config/git/config 由 stow 管理
[user]
    user.name = John Smith
    user.email = john.smith@example.com

[includeIf "gitdir:~/code/git.company-a.net/"]
    path = ~/code/git.company-a.net.gitconfig

; ~/code/git.company-a.net.gitconfig
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_git.company-a.net

[user]
    user.name = John Smith
    user.email = john.smith@company-a.net
```

注意 `[includeIf "gitdir:~/code/git.company-a.net/"]` 配置中目录最后的斜杠 `/`,
这表示 "include for all repositories inside ~/code/git.company-a.net", 没有 `/` 时是精确匹配.

## reference

* https://farseerfc.me/using-gnu-stow-to-manage-your-dotfiles.html
* https://stackoverflow.com/a/43884702
* https://git-scm.com/docs/git-config#_includes
