#!/bin/bash
# author: ak1ra
# date: 2024-12-11
# https://docs.rsshub.app/routes/other#外汇牌价
# 美元 USD 现汇买入价：726.02 现钞买入价：726.02 现汇卖出价：729.07 现钞卖出价：729.07 中行折算价：718.43

set -o errexit -o nounset -o pipefail

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            printf "required command '%s' is not installed, aborting...\n" "$c" 1>&2
            exit 1
        }
    done
}

telegram_send_message() {
    local MESSAGE
    # -t FD, file descriptor FD is opened on a terminal
    if [ -t 0 ]; then
        MESSAGE="$*"
    else
        MESSAGE=$(cat)
    fi

    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${MESSAGE}" \
        -d parse_mode="Markdown" >/dev/null
}

boc_whpj() {
    local currency="$1"
    local whpj_type="$2"

    test -n "${currency}" || currency="USD"
    test -n "${whpj_type}" || whpj_type="现汇卖出价"

    local rsshub="https://rsshub.app"
    local whpj_rss="${rsshub}/boc/whpj/zs?filter_title=${currency}"
    curl -s "${whpj_rss}" |
        xmlstarlet sel -t -m '//item/title[contains(text(),"'"${currency}"'")]/following-sibling::description' \
            -v 'substring-before(substring-after(., "'"${whpj_type}"'："), "<br>")' -n
}

spotify_fee() {
    local months="3"
    local user_count="6"
    local bill_day="17"
    # https://www.spotify.com/us/premium/
    local monthly_fee="19.99"

    local start_date="$(date --date="$(date +%Y-%m-${bill_day})" +%F)"
    local end_date="$(date --date="${start_date} +3 months" +%F)"

    local whpj_base="100"
    local whpj_usd="$(boc_whpj USD 现汇卖出价)"
    local user_fee="$(bc <<<"scale=2;${monthly_fee}*${months}*${whpj_usd}/${whpj_base}/${user_count}")"

    cat <<EOF
大家好,

大家可以开始缴纳本期 Spotify Family 订阅摊分费用了,

本期缴费的生效时间为 ${start_date} ~ ${end_date}, 当前 Spotify 订阅费用为 \`\$${monthly_fee}/mo\`,

按照当前 [中国银行外汇牌价](https://www.boc.cn/sourcedb/whpj/) 美元 的 *现汇卖出价* \`${whpj_usd} CNY / ${whpj_base} USD\`, 本期应收:

\`${monthly_fee} * ${months} * ${whpj_usd} / ${whpj_base} / ${user_count} = ${user_fee} CNY\`
EOF
}

require_command bc xmlstarlet

# BOT_TOKEN="xxxxx:xxxxx" CHAT_ID="-1001234567890" bash ~/bin/spotify-fee.sh
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

spotify_fee "$@" | telegram_send_message
