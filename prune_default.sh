#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

(cat - |
    rg -v '[█©®]' | # invalid characters
    rg -v 'Ã§' | # broken characters, TODO: fix them instead?
    rg -v '[♪♫★]' | # common in subtitles
    rg -v '§ *[^[:digit:]]\|§$' | # paragraph without digit or at the end
    rg -v '[\[\](){}]' | # brackets, parans, braces, https://stackoverflow.com/questions/30044199/how-can-i-match-square-bracket-in-regex-with-grep
    rg -v '[:;"`#~_=+@*^/\\|]' | # characters which complicate sentences
    rg -v '\.\.+' | # more than one dot
    rg -v '^[[:space:][:punct:][:digit:]]*$' | # lines only consisting of spaces, punctuation and digits
    rg -v '[^[:space:]] * [-] * [^[:space:]]' |
    rg '^\p{Lu}' | # must start with uppercase letter \p{Lu} = an uppercase letter that has a lowercase variant. (https://www.regular-expressions.info/unicode.html)
    cat
) || true # rg has non-zero exit code if no lines are matched
