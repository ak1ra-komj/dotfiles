
# tmux
alias tm="tmux attach || tmux"

# using aria2 as external downloader
aria2c_args="--max-concurrent-downloads=8 --max-connection-per-server=16"
## pipx install youtube-dl
alias ytdl="youtube-dl --external-downloader=aria2c --external-downloader-args='$aria2c_args'"
## pipx install yt-dlp
alias ytdlp="yt-dlp --downloader=aria2c --downloader-args=aria2c:'$aria2c_args'"
