#!/usr/bin/bash
# author: ak1ra
# date: 2025-11-13

set -o errexit -o pipefail -o nounset

tempdir="$(mktemp -d /tmp/secrets.XXXXXX)"
trap 'rm -rf "${tempdir}"' EXIT

_print_with_color() {
	color="$1"
	shift
	[ -t 2 ] && printf "\x1b[0;%sm" "${color}" >&2
	echo -n "$*" >&2
	[ -t 2 ] && printf "\x1b[0m\n" >&2
}

_yellow() {
	_print_with_color 33 "$@"
}

main() {
	now="$(date +%s)"
	limit="$((30 * 24 * 3600))"

	while read -r namespace name crt; do
		[[ -n "${crt}" ]] || continue

		# 创建临时文件
		pem="${tempdir}/${namespace}_${name}.pem"
		echo "${crt}" | base64 -d >"${pem}" 2>/dev/null || continue

		subject=$(openssl x509 -in "${pem}" -noout -subject 2>/dev/null | sed 's/^subject= //')
		issuer=$(openssl x509 -in "${pem}" -noout -issuer 2>/dev/null | sed 's/^issuer= //')
		not_after=$(openssl x509 -in "${pem}" -noout -enddate 2>/dev/null | cut -d= -f2)
		expire_ts=$(date -d "${not_after}" +%s 2>/dev/null || true)

		# 非自签证书且 30 天内到期
		if [[ "${subject}" != "${issuer}" ]] && ((expire_ts - now < limit)); then
			echo "=== ${namespace}/${name} ==="
			echo "Subject: ${subject}"
			echo "Issuer : ${issuer}"
			_yellow "Not after: $(date --utc +%Y-%m-%dT%H:%M:%S%Z --date="${not_after}")"
			echo
		fi
	done < <(
		kubectl get secrets --all-namespaces --output=jsonpath='
		{range .items[?(@.type=="kubernetes.io/tls")]}
			{.metadata.namespace} {.metadata.name} {.data.tls\.crt}{"\n"}
		{end}'
	)
}

main "$@"
