#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

cat - |
    grep '[\.?!]$' |
    grep -v '\.\.\.' |
    sed 's/^[-–♪]*\s*//' | # different unicode '-'
    grep -v ' - ' |
    grep -v '[\:\"#]' |
    sed 's/\s*\([\.!?]\)$/\1/' |
    sed 's/(.*)\s*//' | # remove stuff in parantheses
    grep -v '^[[:space:]\.\!\?0-9]*$'
