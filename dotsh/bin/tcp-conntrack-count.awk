#!/usr/bin/gawk -f
# conntrack -L -p tcp | tcp-conntrack-count.awk

BEGIN {
    # 固定 TCP 状态顺序
    split("SYN_SENT SYN_RECV ESTABLISHED FIN_WAIT TIME_WAIT CLOSE_WAIT LAST_ACK CLOSE", state_list, " ")
    n_states = length(state_list)
}

/^tcp/ {
    state = $4

    src = $5
    sub(/^src=/, "", src)

    ip_state[src][state]++
    total[src]++
    ips[src] = 1
}

END {
    # 按 total 连接数降序排序 IP
    PROCINFO["sorted_in"] = "@val_num_desc"

    # -------- 计算列宽 --------
    ip_width = length("SRC_IP")
    for (ip in ips)
        if (length(ip) > ip_width)
            ip_width = length(ip)

    for (i = 1; i <= n_states; i++) {
        col_width[i] = length(state_list[i])
        for (ip in ips) {
            v = ip_state[ip][state_list[i]] + 0
            if (length(v) > col_width[i])
                col_width[i] = length(v)
        }
    }

    # -------- 打印 header --------
    printf "%-*s", ip_width, "SRC_IP"
    for (i = 1; i <= n_states; i++)
        printf " %*s", col_width[i], state_list[i]
    printf " %*s\n", length("TOTAL"), "TOTAL"

    # -------- 打印分隔线 --------
    printf "%-*s", ip_width, "------"
    for (i = 1; i <= n_states; i++) {
        line = ""
        for (j = 1; j <= col_width[i]; j++) line = line "-"
        printf " %s", line
    }
    printf " %s\n", "-----"

    # -------- 打印每个 IP（按 total 排序）--------
    for (ip in total) {
        printf "%-*s", ip_width, ip
        for (i = 1; i <= n_states; i++)
            printf " %*d", col_width[i], ip_state[ip][state_list[i]] + 0
        printf " %*d\n", length("TOTAL"), total[ip]
    }
}
