#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
# set -x # print all commands

FILE=$1
MAX_LINES=${2:-999999999}
MAX_RESULTS=200

# https://www.regular-expressions.info/posixbrackets.html
# https://www.regular-expressions.info/unicode.html
# test string for special chars:  !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
declare -a character_classes=('[[:alpha:]]' '[\p{Letter}&&[^[:alpha:]]]' '\p{Number}' '\p{Punctuation}' '\p{Symbol}' '\p{Separator}')
character_classes+=("[^$(printf "%s" "${character_classes[@]}")]") # append class for everything except the first classes

for i in "${character_classes[@]}"
do
   echo -e "\nCharacter distribution for $i (top 200, max $MAX_LINES lines):"
   head -$MAX_LINES "$FILE" |
       (rg -o "$i" || true) |
       awk -vFS="" '{ w[$0]++ } END {for(i in w) printf "%s %s\n", w[i],i}' |
       sort -rn | 
       head -$MAX_RESULTS | 
       awk 'BEGIN {ORS=""} {printf "%-10s %-1s  ", $1, $2; "echo -n \""$2"\" | xxd -ps -c 200 | tr -d \"\\n\"" | getline hex; printf "%-4s ", hex; gsub("[`\\\\\"]", "\\\\&", $2); system("rg --fixed-strings --max-count 1 --pretty \""$2"\" '"$FILE"'")}'
done


for i in "${character_classes[@]}"
do
    echo -e "\nCharacter distribution for first character $i (top 200, max $MAX_LINES lines):"
    head -$MAX_LINES "$FILE" |
       (rg -o "^$i" || true) |
       awk -vFS="" '{ w[$0]++ } END {for(i in w) print w[i],i}' |
       sort -rn | 
       head -$MAX_RESULTS | 
       awk 'BEGIN {ORS=""} {printf "%-10s %-1s  ", $1, $2; gsub("\\\\", "\\\\", $2);gsub("\\$", "\\$", $2); gsub("[`\\\\\"()\\[\\]\\{\\}\\.\\|\\^\\?\\*\\+]", "\\\\&", $2); system("rg --max-count 1 --pretty \"^"$2"\" '"$FILE"'")}'
done
