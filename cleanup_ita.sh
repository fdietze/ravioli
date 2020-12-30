#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

cat - |
    ./cleanup_default.sh |
    sed "s/\([sS]\)i'/\1ì/" |
    # sed "s/a'/à/" |
    # sed "s/e'/è/" |
    # sed "s/i'/ì/" |
    # sed "s/o'/ò/" |
    # sed "s/u'/ù/" |
    cat
