#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

cat - |
    ./cleanup_default.sh |
    sed 's/\s*\([!?]\)$/ \1/' | # french convention: space before ! and ?
    sed 's/\s*\([\.]\)$/\1/' | # french convention: no space before .
    cat
