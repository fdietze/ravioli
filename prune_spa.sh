#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

(cat - |
    ./prune_default.sh |
    rg '[\.?!]$' |
    rg '^[\p{Lu}¿¡]' | # must start with uppercase letter \p{Lu} = an uppercase letter that has a lowercase variant. (https://www.regular-expressions.info/unicode.html)
    cat
) || true
