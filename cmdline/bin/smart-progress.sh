#! /bin/bash

readarray -t blockdevices < <(
    lsblk --output=path --scsi --json | jq -r .blockdevices[].path | sort
)

selftest_log() {
    for dev in "${blockdevices[@]}"; do
        echo "========== ${dev} =========="
        smartctl --log=selftest "${dev}"
    done
}

selftest_status() {
    echo "========== .ata_smart_data.self_test.status =========="
    for dev in "${blockdevices[@]}"; do
        printf "%s\t%s\n" "${dev}" "$(smartctl -j -c "${dev}" | jq -r .ata_smart_data.self_test.status.string)"
    done
}

selftest_log
selftest_status
