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

# Some sentences have the string '\N' in the language field (unknown language): https://github.com/Tatoeba/tatoeba2/issues/2578
for TRANSLANG in $(echo "select lang from sentences WHERE lang != '\\N' AND lang != '$LANG' AND lang in ('eng', 'fra', 'deu') GROUP BY lang ORDER BY lang ASC" | sqlite3 -init "" "$ALLTRANSLATIONSFILE"); do
    echo "$TRANSLANG";
    TRANSLATIONFILE="$CORPUS_OUT/${LANG}_translated_${TRANSLANG}.sqlite"
    rm -f "$TRANSLATIONFILE"

cat << EOF | sqlite3 -init "" "$TRANSLATIONFILE"

.bail on

CREATE TABLE translations(
  sentenceid INTEGER NOT NULL,
  sentence TEXT NOT NULL UNIQUE,
  level INTEGER NOT NULL
);
CREATE INDEX translations_sentenceid_idx ON translations (sentenceid);
CREATE INDEX translations_level_idx ON translations (level);

attach '$ALLTRANSLATIONSFILE' as tr;
attach '$MODELFILE' as m;

SELECT "  direct translations...";
INSERT OR IGNORE INTO translations (sentenceid, sentence, level)
select s.sentenceid, trs2.sentence, 1
FROM m.sentences s
JOIN tr.sentences trs ON s.sentence = trs.sentence AND trs.lang='$LANG'
JOIN tr.links l ON l.sentenceid = trs.sentenceid
JOIN tr.sentences trs2 ON trs2.sentenceid = l.translationid AND trs2.lang = '$TRANSLANG'
GROUP BY s.sentenceid, trs2.sentence;
select '    ' || count(*) from translations WHERE level = 1;

SELECT "  indirect translations...";
INSERT OR IGNORE INTO translations (sentenceid, sentence, level)
select s.sentenceid, trs2.sentence, 2 
FROM m.sentences s
JOIN tr.sentences trs ON s.sentence = trs.sentence AND trs.lang='$LANG'
JOIN tr.links l ON l.sentenceid = trs.sentenceid
JOIN tr.links l2 ON l2.sentenceid = l.translationid
JOIN tr.sentences trs2 ON trs2.sentenceid = l2.translationid AND trs2.lang = '$TRANSLANG'
GROUP BY s.sentenceid, trs2.sentence;
select '    ' || count(*) from translations WHERE level = 2;

.headers off
SELECT "  vacuum...";
VACUUM;
EOF

done





