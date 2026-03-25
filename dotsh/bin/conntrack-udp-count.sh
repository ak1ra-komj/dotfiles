#!/usr/bin/env bash
# ansible localhost -m copy -a 'src=dotsh/bin/conntrack-udp-count.sh dest=/usr/local/sbin/conntrack-udp-count.sh mode=0755' -v -b

set -o errexit -o nounset

for c in conntrack gawk; do
    if ! command -v "${c}" >/dev/null 2>&1; then
        echo "Required command not found: ${c}" >&2
        exit 1
    fi
done

conntrack -L -p udp | gawk -f <(
    cat <<'EOF'
BEGIN {
    # UDP has no TCP-style states; conntrack marks entries with [UNREPLIED] or [ASSURED].
    # Entries with neither flag are counted as DEFAULT.
    split("UNREPLIED ASSURED DEFAULT", state_list, " ")
    n_states = length(state_list)
}

/^udp/ {
    # Determine status from presence of bracketed flags
    if (/\[UNREPLIED\]/)
        state = "UNREPLIED"
    else if (/\[ASSURED\]/)
        state = "ASSURED"
    else
        state = "DEFAULT"

    # dst= is the first key=value pair after src=
    dst = ""
    for (i = 4; i <= NF; i++) {
        if ($i ~ /^dst=/) {
            dst = $i
            sub(/^dst=/, "", dst)
            break
        }
    }
    if (dst == "") next

    ip_state[dst][state]++
    total[dst]++
    ips[dst] = 1
}

END {
    PROCINFO["sorted_in"] = "@ind_str_asc"

    # -------- calculate column width --------
    ip_width = length("DST_IP")
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

    # -------- print header and separator to stderr --------
    printf "%-*s", ip_width, "DST_IP" > "/dev/stderr"
    for (i = 1; i <= n_states; i++)
        printf " %*s", col_width[i], state_list[i] > "/dev/stderr"
    printf " %*s\n", length("TOTAL"), "TOTAL" > "/dev/stderr"

    printf "%-*s", ip_width, "------" > "/dev/stderr"
    for (i = 1; i <= n_states; i++) {
        line = ""
        for (j = 1; j <= col_width[i]; j++) line = line "-"
        printf " %s", line > "/dev/stderr"
    }
    printf " %s\n", "-----" > "/dev/stderr"

    # -------- print each IP address (sorted by total count) --------
    for (ip in total) {
        printf "%-*s", ip_width, ip
        for (i = 1; i <= n_states; i++)
            printf " %*d", col_width[i], ip_state[ip][state_list[i]] + 0
        printf " %*d\n", length("TOTAL"), total[ip]
    }
}
EOF
)
