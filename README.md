
## README.md for dotfiles

My dotfiles controlled by GNU Stow following [this way](https://farseerfc.me/using-gnu-stow-to-manage-your-dotfiles.html).

### `http_proxy` and `https_proxy`

```
stow http_proxy
cat > ~/.http_proxy.json<<EOF
{
    "proxy_host": "127.0.0.1",
    "proxy_port": 1082,
    "no_proxy": "localhost,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
}
EOF
```
