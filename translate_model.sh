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
select '    ' || count(*) from translations WHERE level = 1;

SELECT "  indirect translations from tatoeba...";
INSERT OR IGNORE INTO translations (sentenceid, sentence, level)
select s.sentenceid, trs2.sentence, 3 
FROM m.sentences s
JOIN tr.sentences trs ON s.sentence = trs.sentence AND trs.lang='$LANG'
JOIN tr.links l ON l.sentenceid = trs.sentenceid
JOIN tr.links l2 ON l2.sentenceid = l.translationid
JOIN tr.sentences trs2 ON trs2.sentenceid = l2.translationid AND trs2.lang = '$TRANSLANG'
GROUP BY s.sentenceid, trs2.sentence;
SELECT '    ' || count(*) from translations WHERE level = 3;
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
SELECT s.sentenceid, t.translation, 2
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
        sqlite3 -init "" "$TRANSLATIONFILE" "INSERT OR IGNORE INTO translations (sentenceid, sentence, level) VALUES ($SENTENCEID, '$TRANSLATED_ESCAPED', 2)"
    else
        break # probably rate limiting issues
    fi
done || true

cat << EOF | sqlite3 -init "" "$TRANSLATIONFILE"
SELECT "  vacuum...";
VACUUM;
EOF
done




