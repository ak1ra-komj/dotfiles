
# tmux
alias tm="tmux attach || tmux"

# youtube-dl
aria2c_args="--max-concurrent-downloads=8 --max-connection-per-server=16"
## python3 -m pip install -U youtube-dl OR apt install youtube-dl
alias ytdl="youtube-dl --external-downloader=aria2c --external-downloader-args='$aria2c_args'"
## python3 -m pip install -U yt-dlp
alias ytdlp="yt-dlp --downloader=aria2c --downloader-args=aria2c:'$aria2c_args'"

# panDownload-php
alias pandl="aria2c --user-agent=LogStatistic --max-concurrent-downloads=8 --max-connection-per-server=16"

# ansible
alias a="ansible"
alias ap="ansible-playbook"
alias apc="ansible-playbook -v --check"
alias adoc="ansible-doc"
