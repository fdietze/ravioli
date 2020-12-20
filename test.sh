#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

SQLITEDB=$1

q() { sqlite3 "$SQLITEDB" -init "" "$@"; }


SENTENCESCOREFN='((1/s_coverage) + AVG(1/p_coverage*(p_proficiency+1)*(p_proficiency+1)))/(matched_patterns*matched_patterns*matched_patterns)' # default proficiency is 0
POTENTIAL_SENTENCE_LIMIT=1000;
PATTERN_LIMIT=1;

GAP=4
# TODO: MAXGAP = log(10000)/log($GAP)


SELECT_NEXT_PATTERNS="SELECT p.pattern FROM patterns p WHERE next_test <= (SELECT time FROM tick LIMIT 1) ORDER BY p.score ASC LIMIT ${PATTERN_LIMIT}"
SELECT_POTENTIAL_SENTENCES="SELECT r.sentenceid, COUNT(DISTINCT p.pattern) as matched_patterns FROM reverseindex r JOIN sentences s ON s.sentenceid = r.sentenceid JOIN patterns p ON r.pattern = p.pattern WHERE p.pattern IN next_patterns GROUP BY r.sentenceid ORDER BY s.coverage DESC LIMIT ${POTENTIAL_SENTENCE_LIMIT}"

# see what will be next and why
cat << EOF | sqlite3 "$SQLITEDB"
.headers on
.mode column

.load ./extension-functions

WITH next_patterns as ($SELECT_NEXT_PATTERNS)
SELECT p.rank, p.pattern, p.score, next_test - (SELECT time FROM tick LIMIT 1) as due_in, proficiency FROM patterns p WHERE p.pattern IN next_patterns GROUP BY p.rank ORDER BY score;


WITH
    next_patterns as ($SELECT_NEXT_PATTERNS),
    potential_sentences as ($SELECT_POTENTIAL_SENTENCES)
SELECT sentenceid, matched_patterns, sentence, group_concat(pattern || '['|| rank ||']' || ': ' || p_proficiency, ', ') as patterns, cast(1/s_coverage as INTEGER) as '1/cov',
-- SELECT coverage, matched_patterns, sentence,  cast(1/coverage as INTEGER) as '1/cov',
        $SENTENCESCOREFN as score
-- SELECT *
FROM (
    SELECT s.sentenceid as sentenceid, ss.sentence as sentence, ss.coverage as s_coverage, matched_patterns, p.pattern, p.rank, p.proficiency as p_proficiency, p.coverage as p_coverage
    FROM potential_sentences as s
    JOIN reverseindex as r ON s.sentenceid = r.sentenceid
    JOIN sentences ss on ss.sentenceid = s.sentenceid
    LEFT OUTER JOIN patterns as p ON r.pattern = p.pattern 
    ORDER BY p.rank
) as inner
GROUP BY sentenceid 
ORDER BY score ASC 
LIMIT 20;


EOF


sentenceid=$(cat << EOF | sqlite3 -init "" "$SQLITEDB"
.headers off
.mode list

.load ./extension-functions
WITH
    next_patterns as (${SELECT_NEXT_PATTERNS}),
    potential_sentences as (${SELECT_POTENTIAL_SENTENCES})
SELECT sentenceid FROM (
    SELECT
        s.sentenceid, ss.coverage as s_coverage, p.coverage as p_coverage, p.proficiency as p_proficiency
    FROM potential_sentences as s
    JOIN reverseindex as r ON s.sentenceid = r.sentenceid
    LEFT OUTER JOIN patterns as p ON r.pattern = p.pattern
    JOIN sentences ss on ss.sentenceid = s.sentenceid
    GROUP BY r.sentenceid
    ORDER BY ${SENTENCESCOREFN} ASC
    LIMIT 1
)
;

EOF
)

echo $sentenceid

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


