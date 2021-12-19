
# tmux
alias tm="tmux attach || tmux"

# youtube-dl
aria2c_args="--max-concurrent-downloads=8 --max-connection-per-server=16"
## python3 -m pip install -U youtube-dl OR apt install youtube-dl
alias ytdl="youtube-dl --external-downloader=aria2c --external-downloader-args='$aria2c_args'"
## python3 -m pip install -U yt-dlp
alias ytdlp="yt-dlp --downloader=aria2c --downloader-args=aria2c:'$aria2c_args'"

