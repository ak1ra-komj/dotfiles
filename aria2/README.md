
## README for aria2 config

releases page: [aria2/releases](https://github.com/aria2/aria2/releases)

### 配置来源

配置基于[这个页面](http://aria2c.com/usage.html)修改而来。

### 关于 rpc-token

本质就是一段随机字符串，为保证安全，尽可能随机。可使用 [DuckDuckGo](https://duckduckgo.com) 快速生成可信 TOKEN: [password 12](https://duckduckgo.com/?q=password+12&ia=answer)

### 关于 bt-tracker

参考这篇文章: [解决 Aria2 BT 下载速度慢没速度的问题](http://www.senra.me/solutions-to-aria2-bt-metalink-download-slowly/), 因为[源文件](https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt)并不是逗号分隔，简单处理一下:

`curl -s https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt | sed '/^$/d' | tr '\n' ',' | sed 's/,$//; s/^\(.*\)/bt-tracker=\1/'`

### 关于 Web-UI

YAAW Web-UI: [yaaw](https://github.com/binux/yaaw)
这是他的 Chrome Extension 版本: [YAAW for Chrome](https://chrome.google.com/webstore/detail/yaaw-for-chrome/dennnbdlpgjgbcjfgaohdahloollfgoc)

一个更现代化的 aria2 Web-UI: [AriaNg](https://github.com/mayswind/AriaNg)
这是他的 Chrome Extension 版本: [YAAW2 for Chrome](https://chrome.google.com/webstore/detail/yaaw2-for-chrome/mpkodccbngfoacfalldjimigbofkhgjn)

### Windows 下开机自启

将以下内容保存为 aria2c.vbs, 根据实际情况修改以下路径。

```
set ws=wscript.createobject("wscript.shell")
ws.Run "/path/to/your/aria2c.exe --conf-path=/path/to/your/aria2.conf",0
```

`Win+R` 输入 `shell:startup` 进入 Windows 启动目录，将刚刚保存的文件 `aria2c.vbs` 放在这个目录。
