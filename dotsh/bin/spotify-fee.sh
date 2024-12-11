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

boc_whpj() {
    currency="$1"
    whpj_type="$2"

    test -n "${currency}" || currency="USD"
    test -n "${whpj_type}" || whpj_type="现汇卖出价"

    rsshub="https://rsshub.app"
    whpj_rss="${rsshub}/boc/whpj/zs?filter_title=${currency}"
    curl -s "${whpj_rss}" |
        xmlstarlet sel -t -m '//item/title[contains(text(),"'"${currency}"'")]/following-sibling::description' \
            -v 'substring-before(substring-after(., "'"${whpj_type}"'："), "<br>")' -n
}

spotify_fee() {
    monthly_fee="19.99"
    months="3"
    users="6"

    whpj_base="100"
    whpj_usd="$(boc_whpj USD 现汇卖出价)"
    user_fee="$(bc <<<"scale=2;${monthly_fee}*${months}*${whpj_usd}/${whpj_base}/${users}")"

    cat <<EOF
各位可以开始缴纳本期 (未来 3 个月) Spotify Family 订阅摊分费用了,

目前 Spotify 订阅费用为 \$${monthly_fee}/mo,

按目前 中国银行外汇牌价 美元 的 现汇卖出价 ${whpj_usd}, 本期应收,

${monthly_fee} * ${months} * ${whpj_usd} / ${whpj_base} / ${users} = ${user_fee} CNY

---
中国银行外汇牌价 (本汇率表单位为 ${whpj_base} 外币换算人民币):
https://www.boc.cn/sourcedb/whpj/

EOF
}

require_command bc xmlstarlet

spotify_fee "$@"
