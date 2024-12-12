#!/bin/bash
# author: ak1ra
# date: 2024-12-11
# BOT_TOKEN="xxxxx:xxxxx" CHAT_ID="-1001234567890" bash ~/bin/spotify-fee.sh

set -o errexit -o pipefail

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            printf "required command '%s' is not installed, aborting...\n" "$c" 1>&2
            exit 1
        }
    done
}

get_exchange_rate() {
    local currency="$1"
    test -n "${currency}" || currency="USD"

    # https://docs.rsshub.app/routes/other#外汇牌价
    # <title>美元 USD 现汇卖出价：728.87</title>
    local rsshub="https://rsshub.app"
    # curl -s https://rsshub.app/boc/whpj/xhmc?filter_title=USD | xmlstarlet sel -t -m '//item/title[contains(text(),"USD")]' -v 'substring-after(., "现汇卖出价：")' -n
    local exchange_rate_rss="${rsshub}/boc/whpj/xhmc?filter_title=${currency}"
    (
        set -x
        curl -s "${exchange_rate_rss}" |
            xmlstarlet sel -t -m '//item/title[contains(text(),"'"${currency}"'")]' \
                -v 'substring-after(., "现汇卖出价：")' -n
    )
}

create_spotify_fee_message() {
    local months="3"
    local user_count="6"
    local billing_day="17"
    # https://www.spotify.com/us/premium/
    local monthly_fee="19.99"
    local exchange_base="100"
    local start_date end_date exchange_rate user_fee

    start_date="$(date --date="$(date +%Y-%m-${billing_day})" +%F)"
    end_date="$(date --date="${start_date} +${months} months" +%F)"
    exchange_rate="$(get_exchange_rate USD)"
    user_fee="$(bc <<<"scale=2;${monthly_fee}*${months}*${exchange_rate}/${exchange_base}/${user_count}")"

    cat <<EOF
大家好,

大家可以开始缴纳本期 Spotify Family 订阅摊分费用了,

本期缴费的生效时间为 *${start_date} ~ ${end_date}*, 当前 Spotify 订阅费用为 *\$${monthly_fee}/mo*. 按照当前 [中国银行外汇牌价](https://www.boc.cn/sourcedb/whpj/) 美元 的 *现汇卖出价* ${exchange_rate} USD / ${exchange_base} CNY, 本期应收,

\`${monthly_fee} * ${months} * ${exchange_rate} / ${exchange_base} / ${user_count} = ${user_fee} CNY\`
EOF
}

send_telegram_message() {
    local MESSAGE
    # -t FD, file descriptor FD is opened on a terminal
    if [ -t 0 ]; then
        MESSAGE="$*"
    else
        MESSAGE=$(cat)
    fi

    (
        set -x
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d chat_id="${CHAT_ID}" \
            -d text="${MESSAGE}" \
            -d parse_mode="Markdown" >/dev/null
    )
}

main() {
    local message
    message="$(create_spotify_fee_message)"

    if [ -n "${BOT_TOKEN}" ] && [ -n "${CHAT_ID}" ]; then
        send_telegram_message "${message}"
    else
        echo "${message}"
    fi
}

require_command bc xmlstarlet

main "$@"
