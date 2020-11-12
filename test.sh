#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

SQLITEDB=$1

q() { sqlite3 "$SQLITEDB" -init "" "$@"; }


PATTERNSCOREFN='2*(1/p.coverage) + MIN(1/s.coverage)'
# PATTERNSCOREFN='(1/p.coverage) + MIN(1/s.coverage)'
# PATTERNSCOREFN='(1/p.coverage) + sqrt(MIN(1/s.coverage))'
SENTENCESCOREFN='(1/ss.coverage) + AVG(1/p.coverage*(p.proficiency+1)*(p.proficiency+1))' # default proficiency is 0
GAP=4
# TODO: MAXGAP = log(10000)/log($GAP)

# see what will be next
# cat << EOF | sqlite3 "$SQLITEDB"
# .headers on
# .mode column

# .load ./extension-functions

# SELECT p.rank, p.pattern, $PATTERNSCOREFN as score, next_test - (SELECT time FROM tick LIMIT 1) as due, proficiency FROM patterns p JOIN reverseindex r ON r.pattern = p.pattern JOIN sentences s ON s.sentenceid = r.sentenceid WHERE next_test <= (SELECT time FROM tick LIMIT 1) GROUP BY p.rank ORDER BY score LIMIT 10;

# ;

# -- SELECT rank, pattern, proficiency, next_test FROM patterns WHERE next_test <= (SELECT time FROM tick LIMIT 1) ORDER BY rank ASC limit 3;


# WITH
#     next_patterns as (SELECT p.pattern FROM patterns p JOIN reverseindex r ON r.pattern = p.pattern JOIN sentences s ON s.sentenceid = r.sentenceid WHERE next_test <= (SELECT time FROM tick LIMIT 1) GROUP BY p.rank ORDER BY $PATTERNSCOREFN LIMIT 1),
#     potential_sentences as ( SELECT sentenceid FROM reverseindex WHERE pattern IN next_patterns)
# SELECT s.sentenceid, ss.sentence, group_concat(p.pattern || '['|| p.rank ||']' || ': ' || p.proficiency, ', ') as patterns, cast(1/ss.coverage as INTEGER) as '1/cov',
#         $SENTENCESCOREFN as score
# FROM potential_sentences as s
# JOIN reverseindex as r ON s.sentenceid = r.sentenceid
# JOIN sentences ss on ss.sentenceid = s.sentenceid
# LEFT OUTER JOIN patterns as p ON r.pattern = p.pattern 
# GROUP BY r.sentenceid 
# ORDER BY score ASC 
# LIMIT 20;
# EOF


sentenceid=$(cat << EOF | sqlite3 -init "" "$SQLITEDB"
.headers off
.mode list

.load ./extension-functions

WITH
    next_patterns as (SELECT p.pattern FROM patterns p JOIN reverseindex r ON r.pattern = p.pattern JOIN sentences s ON s.sentenceid = r.sentenceid WHERE next_test <= (SELECT time FROM tick LIMIT 1) GROUP BY p.rank ORDER BY $PATTERNSCOREFN LIMIT 1),
    potential_sentences as ( SELECT sentenceid FROM reverseindex WHERE pattern IN next_patterns)
SELECT
    s.sentenceid
FROM
    potential_sentences as s
JOIN reverseindex as r ON s.sentenceid = r.sentenceid
LEFT OUTER JOIN patterns as p ON r.pattern = p.pattern
JOIN sentences ss on ss.sentenceid = s.sentenceid
GROUP BY r.sentenceid
ORDER BY $SENTENCESCOREFN ASC
LIMIT 1
;
EOF
)

# if no more pattern needs to be trained, advance in time
if [ -z "$sentenceid" ]; then
    q "UPDATE tick SET time = time + 1"
    exit 0;
fi


# echo "sentenceid: '$sentenceid'"

sentence=$(q "SELECT sentence FROM sentences where sentenceid = $sentenceid")

# echo "sentence: $sentence"

time=$(q "SELECT time from tick LIMIT 1")
# next=$(q "SELECT group_concat(p.pattern || '['|| p.rank ||']' || ': ' || (p.next_test - $time), ', ') from reverseindex r JOIN patterns p ON r.pattern = p.pattern  WHERE sentenceid = $sentenceid;")

echo "$time: $sentence"

IFS=$'\n'
patterns=(`q "SELECT p.rank from reverseindex r JOIN patterns p ON r.pattern = p.pattern  WHERE sentenceid = $sentenceid"`)

for rank in "${patterns[@]}"; do
    q -cmd ".load ./extension-functions" "UPDATE patterns SET proficiency = proficiency + 1, next_test = (SELECT time from tick LIMIT 1) + power($GAP, max(0, min(8, proficiency+2))) WHERE rank = '$rank';"
    # q -cmd ".load ./extension-functions" "UPDATE patterns SET proficiency = proficiency - 1, next_test = (SELECT time from tick LIMIT 1) + $GAP WHERE rank = '$rank';"
done

q "UPDATE tick SET time = time + 1"


