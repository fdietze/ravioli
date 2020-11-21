#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
shopt -s expand_aliases



CORPUS=$1
LANG=$2
ALLTRANSLATIONSFILE=$3

OUT="out"
CORPUS_OUT="$OUT/$CORPUS"
mkdir -p "$CORPUS_OUT"
MODELFILE="$CORPUS_OUT/${LANG}_model.sqlite"

./create_translation_db.sh

function missing_translations() {
    MODELFILE=$1
    TRANSLATIONFILE=$2
cat << EOF | sqlite3 -init "" "$TRANSLATIONFILE"
.mode tabs
attach '$MODELFILE' as m;
SELECT s.sentenceid, s.sentence
FROM m.sentences s
LEFT OUTER JOIN translations t on s.sentenceid = t.sentenceid
WHERE t.sentenceid IS NULL
ORDER BY s.coverage DESC;
EOF
}

# Some sentences have the string '\N' in the language field (unknown language): https://github.com/Tatoeba/tatoeba2/issues/2578
for TRANSLANG in $(echo "select lang from sentences WHERE lang != '\\N' AND lang != '$LANG' AND lang in ('eng', 'fra', 'deu') GROUP BY lang ORDER BY lang ASC" | sqlite3 -init "" "$ALLTRANSLATIONSFILE"); do
    echo "$TRANSLANG";
    TRANSLATIONFILE="$CORPUS_OUT/${LANG}_translated_${TRANSLANG}.sqlite"
    rm -f "$TRANSLATIONFILE"

cat << EOF | sqlite3 -init "" "$TRANSLATIONFILE"
.bail on

CREATE TABLE translations(
  sentenceid INTEGER NOT NULL,
  sentence TEXT NOT NULL,
  level INTEGER NOT NULL,

  UNIQUE(sentenceid, sentence)
);
CREATE INDEX translations_sentenceid_idx ON translations (sentenceid);
CREATE INDEX translations_level_idx ON translations (level);
EOF


cat << EOF | sqlite3 -init "" "$TRANSLATIONFILE"
attach '$ALLTRANSLATIONSFILE' as tr;
attach '$MODELFILE' as m;

SELECT "  direct translations from tatoeba...";
INSERT OR IGNORE INTO translations (sentenceid, sentence, level)
    select s.sentenceid, trs2.sentence, 1
    FROM m.sentences s
    JOIN tr.sentences trs ON s.sentence = trs.sentence AND trs.lang='$LANG'
    JOIN tr.links l ON l.sentenceid = trs.sentenceid
    JOIN tr.sentences trs2 ON trs2.sentenceid = l.translationid AND trs2.lang = '$TRANSLANG'
    GROUP BY s.sentenceid, trs2.sentence;
select '    total: ' || count(*) from translations;




SELECT "  indirect translations from tatoeba...";
-- "A  -- X  -- O  -- X  -- A"
-- "s1 -- s2 -- s3 -- s4 -- s5"
-- "s1  -l1->  s2  -l2->  s3  -l3->  s4  -l4->  s5"
INSERT OR IGNORE INTO translations (sentenceid, sentence, level)
    SELECT sentenceid, translation as sentence, (CASE WHEN COUNT(*) > 100 THEN 1 ELSE 2 END) as level FROM (
        SELECT s.sentenceid, s3.sentence as translation
        FROM m.sentences s
        JOIN tr.sentences s1 ON s.sentence = s1.sentence
        JOIN tr.links l1 ON l1.sentenceid = s1.sentenceid
        JOIN tr.links l2 ON l2.sentenceid = l1.translationid
        JOIN tr.sentences s3 ON s3.sentenceid = l2.translationid
        JOIN tr.links l3 ON l3.sentenceid = l2.translationid
        JOIN tr.links l4 ON l4.sentenceid = l3.translationid
        WHERE
                s1.lang = '$LANG'
            AND s3.lang = '$TRANSLANG'
            AND l4.translationid = s1.sentenceid -- close cycle

            AND s1.sentenceid != l1.translationid
            AND l1.translationid != l2.translationid
            AND l2.translationid != l3.translationid
    )
    GROUP BY translation
    HAVING COUNT(*) > 10;
select '    total: ' || count(*) from translations;
EOF


echo "machine translations from cache..."
if [ -s "$HOME/.cache/trans_cache.sqlite" ]; then
cat << EOF | sqlite3 -init "" "$TRANSLATIONFILE"
.bail on
attach '$MODELFILE' as m;
attach '$HOME/.cache/trans_cache.sqlite' as cache;

INSERT OR IGNORE INTO translations (sentenceid, sentence, level)
WITH missing AS (
    SELECT s.sentenceid, s.sentence
    FROM m.sentences s
    LEFT OUTER JOIN translations t on s.sentenceid = t.sentenceid
    WHERE t.sentenceid IS NULL
    )
SELECT s.sentenceid, t.translation, 3
FROM missing s
JOIN cache.translations t ON t.text = s.sentence
WHERE t.sourcelang = '$LANG' AND t.targetlang = '$TRANSLANG'
EOF
fi

echo "machine translations via api..."
missing_translations "$MODELFILE" "$TRANSLATIONFILE" | sponge | while read -r SENTENCEID SENTENCE; do
    TRANSLATED=$(./machine-translate.sh "$LANG" "$TRANSLANG" "$SENTENCE")
    if [ -n "$TRANSLATED" ]; then
        echo "    $SENTENCE -> '$TRANSLATED'"
        TRANSLATED_ESCAPED=$(echo "$TRANSLATED" | sed "s/'/''/g" | ./normalize_unicode.sh)
        sqlite3 -init "" "$TRANSLATIONFILE" "INSERT OR IGNORE INTO translations (sentenceid, sentence, level) VALUES ($SENTENCEID, '$TRANSLATED_ESCAPED', 3)"
    else
        break # probably rate limiting issues
    fi
done || true

cat << EOF | sqlite3 -init "" "$TRANSLATIONFILE"
SELECT "  vacuum...";
VACUUM;
EOF
done




