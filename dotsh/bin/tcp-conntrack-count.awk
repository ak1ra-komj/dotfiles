#!/usr/bin/gawk -f
# sudo conntrack -L -p tcp | tcp-conntrack-count.awk
# ansible localhost -m copy -a 'src=dotsh/bin/tcp-conntrack-count.awk dest=/usr/local/bin/tcp-conntrack-count.awk mode=0755' -v -b

BEGIN {
    # fixed TCP state sequence
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
    # Sort the IP addresses in descending order by the total number of connections.
    PROCINFO["sorted_in"] = "@val_num_desc"

    # -------- calculate column width --------
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

    # -------- print header --------
    # printf "%*s", width_value, string_value
    # The asterisk (*) is a placeholder for the width value,
    # which is taken from the argument list immediately preceding the string to be printed.
    printf "%-*s", ip_width, "SRC_IP"
    for (i = 1; i <= n_states; i++)
        printf " %*s", col_width[i], state_list[i]
    printf " %*s\n", length("TOTAL"), "TOTAL"

    # -------- print separator line --------
    printf "%-*s", ip_width, "------"
    for (i = 1; i <= n_states; i++) {
        line = ""
        for (j = 1; j <= col_width[i]; j++) line = line "-"
        printf " %s", line
    }
    printf " %s\n", "-----"

    # -------- print each IP address (sorted by total count) --------
    for (ip in total) {
        printf "%-*s", ip_width, ip
        for (i = 1; i <= n_states; i++)
            printf " %*d", col_width[i], ip_state[ip][state_list[i]] + 0
        printf " %*d\n", length("TOTAL"), total[ip]
    }
}
