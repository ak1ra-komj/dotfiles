
# tmux
alias tm="tmux attach || tmux"

# aria2
aria2c_args="--max-concurrent-downloads=8 --max-connection-per-server=16"
## python3 -m pip install -U youtube-dl yt-dlp
alias ytdl="youtube-dl --external-downloader=aria2c --external-downloader-args='$aria2c_args'"
alias ytdlp="yt-dlp --downloader=aria2c --downloader-args=aria2c:'$aria2c_args'"
# panDownload-php
alias pandl="aria2c --user-agent=LogStatistic $aria2c_args"
