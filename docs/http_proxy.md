
## `stow http_proxy`

如果需要使用 `http_proxy` 为命令行工具配置 HTTP Proxy, 需要自行在 $HOME 目录下创建一个叫 `~/.http_proxy.json` 的文件, 内容如下, 将 `proxy_host` 和 `proxy_port` 替换为自己实际配置.

```shell
stow http_proxy
cat > ~/.http_proxy.json<<EOF
{
    "proxy_host": "127.0.0.1",
    "proxy_port": 1082,
    "no_proxy": "localhost,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
}
EOF
```
