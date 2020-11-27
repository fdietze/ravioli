#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
shopt -s expand_aliases

export LC_ALL=en_US.UTF-8 

# https://www.fontspace.com/unicode/analyzer

# https://en.wikipedia.org/wiki/Unicode_equivalence#Combining_and_precomposed_characters
# https://www.effectiveperlprogramming.com/2011/09/normalize-your-perl-source/
alias nfd="perl -MUnicode::Normalize -CS -ne 'print NFD(\$_)'" # decomposed characters
alias nfc="perl -MUnicode::Normalize -CS -ne 'print NFC(\$_)'" # composed characters

# Normalize different unicode space characters to the same space
# https://stackoverflow.com/a/43640405
alias normalize_spaces="perl -CSDA -plE 's/[^\\S\\t]/ /g'"

# https://unix.stackexchange.com/questions/6516/filtering-invalid-utf8
alias strip_invalid_lines="rg -ax '.*'"

cat - | strip_invalid_lines | normalize_spaces | nfc
