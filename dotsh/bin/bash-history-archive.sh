#!/usr/bin/env bash

set -o errexit -o nounset

readonly MAX_LINES=10000
readonly HISTORY_FILE="${HOME}/.bash_history"
readonly ARCHIVE_FILE="${HOME}/.bash_history.archive"

if [[ ! -f "${HISTORY_FILE}" ]]; then
    exit 0
fi

linecount=$(wc -l <"${HISTORY_FILE}")

if ((linecount <= MAX_LINES)); then
    exit 0
fi

umask 077

prune_lines=$((linecount - MAX_LINES))
temp_file="${HISTORY_FILE}.tmp$$"
trap 'rm -f "${temp_file}"' EXIT

tail -n "+$((prune_lines + 1))" "${HISTORY_FILE}" >"${temp_file}"
head -n "${prune_lines}" "${HISTORY_FILE}" >>"${ARCHIVE_FILE}"
mv "${temp_file}" "${HISTORY_FILE}"

echo "Archived ${prune_lines} lines to ${ARCHIVE_FILE}"
