#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
# shopt -s expand_aliases

DBFILE=${1:-"out/translations_opensub/translations.sqlite"}
SOURCELANG=${2:-'fra'}
SENTENCE=${3:-'Salut.'}
MIN_COVERAGE=0.5

SENTENCE=$(echo "${SENTENCE//\'/\'\'}" | ./normalize_unicode.sh) # escape single quotes for sqlite

cat << EOF | sqlite3 -init "" "$DBFILE"
.mode column
.headers on

SELECT sentenceid, sentence
FROM sentences
WHERE
    sentence = '$SENTENCE' AND lang = '$SOURCELANG'
;
EOF

echo ""

cat << EOF | sqlite3 -init "" "$DBFILE"
.mode column
.headers on
-- .width auto auto auto

.output /dev/null
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
pragma mmap_size = 30000000000;
pragma threads = 4;
.output


.headers off
SELECT "";
SELECT "Paraphrases:";
.headers on
-- #    /-- X --\
-- #  S --- Y --- ST
-- #    \-- Z --|
-- #    \--...--/



SELECT sentence, prob, cumulative
FROM (
    SELECT sentenceid, sentence, prob, SUM(prob) OVER (ROWS UNBOUNDED PRECEDING) as cumulative
    FROM (
        SELECT ts.sentenceid, ts.sentence, sum(probability) as prob
        FROM sentences s
        JOIN indirect_translations_ungrouped t
            ON t.sourceid = s.sentenceid AND t.lang = '$SOURCELANG'
        JOIN sentences ts ON ts.sentenceid = t.targetid
        WHERE s.sentence = '$SENTENCE' AND s.lang = '$SOURCELANG'
        GROUP BY t.targetid
        HAVING COUNT(DISTINCT pivot_lang) >= 3
        ORDER BY prob DESC
    )
)
WHERE cumulative - prob <= $MIN_COVERAGE
;

EOF
