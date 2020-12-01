#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
# shopt -s expand_aliases

PATH=$PATH:$HOME/projects/postgresqlite


DBFILE=${1-"out/translations/translations.pg"}
SOURCELANG=${2-'fra'}
TARGETLANG=${3-'deu'}
SENTENCE=${4-'Salut.'}

SENTENCE=$(echo "$SENTENCE" | sed "s/'/''/g" | ./normalize_unicode.sh) # escape single quotes for sqlite


SQL=$(cat << EOF
SELECT sentenceid, sentence
FROM sentences
WHERE
    sentence = '$SENTENCE' AND lang = '$SOURCELANG'
EOF
)
postgresqlite "$DBFILE" "$SQL"

exit

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




SELECT t.sentence, probability
FROM sentences s
JOIN direct_translations d ON d.sourceid = s.sentenceid
JOIN sentences t ON t.sentenceid = d.targetid
WHERE d.lang = '$TARGETLANG' AND s.sentence = '$SENTENCE' AND s.lang = '$SOURCELANG'
ORDER BY probability DESC;



.headers off
SELECT "";
SELECT "indirect translations...";
.headers on
-- #    /-- X --\
-- #  S --- Y --- ST
-- #    \-- Z --|
-- #    \--...--/



-- EXPLAIN QUERY PLAN
SELECT ts.sentence, GROUP_CONCAT(pivot_lang), sum(probability)
FROM sentences s
JOIN indirect_translations_ungrouped t
    ON t.sourceid = s.sentenceid AND t.lang = '$TARGETLANG'
JOIN sentences ts ON ts.sentenceid = t.targetid
WHERE s.sentence = '$SENTENCE' AND s.lang = '$SOURCELANG'
GROUP BY t.targetid
HAVING COUNT(DISTINCT pivot_lang) >= 2
ORDER BY sum(probability) DESC;



-- SELECT s.sentence, ts.lang, ts.sentence, sum(probability) as probability
-- FROM sentences s
-- JOIN indirect_translations_ungrouped t ON t.sourceid = s.sentenceid
-- JOIN sentences ts ON ts.sentenceid = t.targetid
-- WHERE s.sentenceid < 1000
-- GROUP BY s.sentenceid, t.targetid
-- HAVING sum(probability) > 0.1
-- ORDER BY s.sentenceid, probability DESC
-- ;



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


EOF
