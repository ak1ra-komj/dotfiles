#!/bin/bash
# author: ak1ra
# date: 2025-04-11

map_ids() {
	# declare -n, making it a name reference to another variable.
	# shellcheck disable=SC2034
	local -n nameref_map=$1
	local find_pattern="$2"
	local grep_exclude="$3"

	while IFS= read -r link; do
		dev=$(readlink -f "$link")
		dev_basename=$(basename "$dev")
		link_basename=$(basename "$link")
		# shellcheck disable=SC2034
		nameref_map["$dev_basename"]="$link_basename"
	done < <(
		find /dev/disk/by-id -type l \
			-regextype posix-extended -regex "$find_pattern" |
			grep -vE -- '-part[0-9]+$' | {
			if [[ -n "$grep_exclude" ]]; then
				grep -vE -- "$grep_exclude"
			else
				cat
			fi
		}
	)
}

# declare -A dev_eui_map
# declare -A dev_nvme_map
# map_ids dev_eui_map "/dev/disk/by-id/nvme-eui\..*" ""
# map_ids dev_nvme_map "/dev/disk/by-id/nvme-.*" "nvme-eui\."

# for dev in "${!dev_eui_map[@]}"; do
# 	printf "%s\t%s\n" "${dev_eui_map[$dev]}" "${dev_nvme_map[$dev]:-(no nvme-ID found)}"
# done

declare -A dev_wwn_map
declare -A dev_ata_map
map_ids dev_wwn_map "/dev/disk/by-id/wwn-.*" ""
map_ids dev_ata_map "/dev/disk/by-id/(ata|scsi)-.*" ""

for dev in "${!dev_wwn_map[@]}"; do
	printf "%s\t%s\n" "${dev_wwn_map[$dev]}" "${dev_ata_map[$dev]:-(no ata-ID found)}"
done
