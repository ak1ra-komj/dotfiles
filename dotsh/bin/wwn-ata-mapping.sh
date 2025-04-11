#!/bin/bash
# author: ak1ra
# date: 2025-04-11

# Create temp maps for ata and wwn
declare -A dev_ata_map
declare -A dev_wwn_map

# Populate ATA map
while IFS= read -r link; do
    dev=$(readlink -f "$link")
    dev_name=$(basename "$dev")
    ata_name=$(basename "$link")
    dev_ata_map["$dev_name"]="$ata_name"
done < <(find /dev/disk/by-id/ -type l -name 'ata-*' ! -name '*-part*' | sort)

# Populate WWN map
while IFS= read -r link; do
    dev=$(readlink -f "$link")
    dev_name=$(basename "$dev")
    wwn_name=$(basename "$link")
    dev_wwn_map["$dev_name"]="$wwn_name"
done < <(find /dev/disk/by-id/ -type l -name 'wwn-*' ! -name '*-part*' | sort)

# Print mapping
for dev in "${!dev_wwn_map[@]}"; do
    ata="${dev_ata_map[$dev]}"
    wwn="${dev_wwn_map[$dev]}"
    if [[ -n "${ata}" ]]; then
        printf "%s\t%s\n" "${wwn}" "${ata}"
    else
        printf "%s\t(no ata-ID found)\n" "${wwn}"
    fi
done | sort -k2
