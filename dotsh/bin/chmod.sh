#!/bin/sh

set -o errexit -o nounset

main() {
    if [ "$#" -eq 1 ]; then
        mode="$1"
    else
        mode="644"
    fi

    case "${mode}" in
        600)
            # credential files like ~/.ssh
            # 600 for files, 700 for directories
            chmod -R "u=rwX,g=---,o=---" .
            ;;
        660)
            # TrueNAS Samba share for guests
            # 660 for files, 770 for directories
            chmod -R "u=rwX,g=rwX,o=---" .
            ;;
        664)
            # TrueNAS Samba share for users
            # 664 for files, 775 for directories
            chmod -R "u=rwX,g=rwX,o=r-X" .
            ;;
        644)
            # defaut
            # 644 for files, 755 for directories
            chmod -R "u=rwX,g=r-X,o=r-X" .
            ;;
        *)
            chmod --help
            ;;
    esac
}

main "$@"
