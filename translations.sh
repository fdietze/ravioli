#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
# shopt -s expand_aliases

DBFILE=${1:-"out/translations_opensub/translations.sqlite"}
SOURCELANG=${2:-'fra'}
TARGETLANG=${3:-'deu'}
SEARCHTERM=${4:-'Salut.'}
MIN_COVERAGE=0.5

SEARCHTERM=$(echo "${SEARCHTERM//\'/\'\'}" | ./normalize_unicode.sh) # escape single quotes for sqlite


SENTENCES=$(cat << EOF | sqlite3 -init "" "$DBFILE"
.mode tabs
.headers off

SELECT sentenceid, occurrences, sentence
FROM sentences
WHERE lang = '$SOURCELANG' and sentence LIKE '$SEARCHTERM'
ORDER BY occurrences DESC LIMIT 20;

EOF
)
echo "$SENTENCES"

SENTENCEID=$(echo "$SENTENCES" | head -1 | cut -f1)
SENTENCE=$(echo "$SENTENCES" | head -1 | cut -f3-)

if [ -z "$SENTENCES" ]; then
    exit 1;
fi

echo -e "\nTranslating: '$SENTENCE' ($SOURCELANG) -> $TARGETLANG\n"

cat << EOF | sqlite3 -init "" "$DBFILE"
.mode column
.headers on
.width 60 auto auto

.output /dev/null
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
pragma mmap_size = 30000000000;
pragma threads = 4;
.output




.headers off
SELECT "direct translations:";
.headers on

SELECT sentence, probability, cumulative
FROM (
    SELECT sentence, probability, SUM(probability) OVER (ROWS UNBOUNDED PRECEDING) as cumulative
    FROM (
        SELECT t.sentence, probability
        FROM direct_translations d
        JOIN sentences t ON t.sentenceid = d.targetid
        WHERE d.lang = '$TARGETLANG' AND d.sourceid = '$SENTENCEID'
        ORDER BY probability DESC
    )
)
WHERE cumulative - probability <= $MIN_COVERAGE
;



.headers off
SELECT "";
SELECT "indirect translations:";
.headers on
-- #    /-- X --\
-- #  S --- Y --- ST
-- #    \-- Z --|
-- #    \--...--/


-- EXPLAIN QUERY PLAN
SELECT sentence, prob as probability, cumulative
FROM (
    SELECT sentenceid, sentence, prob, SUM(prob) OVER (ROWS UNBOUNDED PRECEDING) as cumulative
    FROM (
        SELECT ts.sentenceid, ts.sentence, sum(probability) as prob
        FROM indirect_translations_ungrouped t
        JOIN sentences ts ON ts.sentenceid = t.targetid
        WHERE t.sourceid = '$SENTENCEID' AND t.lang = '$TARGETLANG'
        GROUP BY t.targetid
        HAVING COUNT(DISTINCT pivot_lang) >= 2
        ORDER BY prob DESC
    )
)
WHERE cumulative - prob <= $MIN_COVERAGE
;


-- WITH source as (SELECT * FROM sentences WHERE lang = '$SOURCELANG' AND sentence = '$SENTENCE'),
--      data as (
--     SELECT
--         sp.lang as pivot_lang,
--         st.sentence,
--         st.sentenceid,
--         l.l1_occurrences * l.l2_occurrences as occurrences
--     FROM chain2_acyclic l
--     JOIN source s  ON s.sentenceid  = l.sentenceid
--     JOIN sentences sp  ON sp.sentenceid  = l.l1_translationid
--     JOIN sentences st ON st.sentenceid = l.l2_translationid
--     WHERE
--         st.lang = '$TARGETLANG'
--     UNION ALL
--     SELECT '','',0,0 WHERE 0 = 1 -- forces sqlite to use temp b-tree for grouping
-- )
-- SELECT sentence, GROUP_CONCAT(pivot_lang), CAST(sum(occurrences) as real)/(SELECT degree2 FROM lang_degree2 d2 WHERE d2.sentenceid IN (SELECT sentenceid FROM source) AND d2.lang = '$TARGETLANG') as probability
-- FROM data
-- GROUP BY sentenceid
-- HAVING COUNT(distinct pivot_lang) >= 2
-- ORDER BY probability DESC
-- ;
;


EOF
