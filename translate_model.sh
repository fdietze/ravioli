#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
shopt -s expand_aliases

main() {

CORPUS=$1
SOURCELANG=$2
TATOEBA="out/translations_tatoeba/translations.sqlite"
OPENSUB="out/translations_opensub/translations.sqlite"

OUT="out"
CORPUS_OUT="$OUT/$CORPUS"
mkdir -p "$CORPUS_OUT"
MODELFILE="$CORPUS_OUT/${SOURCELANG}_model.sqlite"
MIN_COVERAGE=0.5
MACHINE_PROBABILITY=0.05

translation-stats $OPENSUB OpenSubtitles
translation-stats $TATOEBA Tatoeba

rm -f "$CORPUS_OUT/${SOURCELANG}"_translated_*.sqlite
for TARGETLANG in $(available-target-languages "$OPENSUB"); do
    echo "$SOURCELANG -> $TARGETLANG";
    TRANSLATIONTARGETFILE="$CORPUS_OUT/${SOURCELANG}_translated_${TARGETLANG}.sqlite"

    init-translationdb                                                      "$TRANSLATIONTARGETFILE"
    add-direct-translations   "$OPENSUB" OpenSub "$TARGETLANG" "$MODELFILE" "$TRANSLATIONTARGETFILE"
    add-indirect-translations "$OPENSUB" OpenSub "$TARGETLANG" "$MODELFILE" "$TRANSLATIONTARGETFILE"
    add-indirect-translations "$TATOEBA" Tatoeba "$TARGETLANG" "$MODELFILE" "$TRANSLATIONTARGETFILE"
    add-direct-translations   "$TATOEBA" Tatoeba "$TARGETLANG" "$MODELFILE" "$TRANSLATIONTARGETFILE"
    add-machine-translations-cache               "$TARGETLANG" "$MODELFILE" "$TRANSLATIONTARGETFILE"
    add-machine-translations-api                 "$TARGETLANG" "$MODELFILE" "$TRANSLATIONTARGETFILE"
    finish-translationdb                                                    "$TRANSLATIONTARGETFILE"
done
}

translation-stats() {
TRANSLATIONFILE=$1
NAME=$2
cat << EOF | sqlite3 -init ""
.bail on
attach '$MODELFILE' as m;
attach '$TRANSLATIONFILE' as tr;
SELECT 'sentence coverage ($NAME): ' || (cast(count(*) AS real)/(SELECT count(*) FROM m.sentences)) FROM m.sentences s JOIN tr.sentences trs ON s.sentence = trs.sentence AND trs.lang = '$SOURCELANG';
EOF
}

available-target-languages() {
TRANSLATIONFILE=$1
echo "SELECT lang FROM sentences WHERE lang != '$SOURCELANG' GROUP BY lang ORDER BY lang ASC" |
    sqlite3 -init "" "$TRANSLATIONFILE"
}

init-translationdb() {
TRANSLATIONTARGETFILE=$1
if [ ! -s "$TRANSLATIONTARGETFILE" ]; then
cat << EOF | sqlite3 -init "" "$TRANSLATIONTARGETFILE"
.bail on

CREATE TABLE translations(
  sentenceid INTEGER NOT NULL,
  translation TEXT NOT NULL,
  probability REAL NOT NULL,

  PRIMARY KEY(sentenceid, translation)
);
EOF
fi
}

add-direct-translations() {
TRANSLATIONFILE=$1
NAME=$2
TARGETLANG=$3
MODELFILE=$4
TRANSLATIONTARGETFILE=$5

echo "  direct translations from $NAME...";
MISSING_BEFORE=$(missing-translations-count "$MODELFILE" "$TRANSLATIONTARGETFILE")
missing-translations "$MODELFILE" "$TRANSLATIONTARGETFILE" | sponge | while read -r SENTENCEID SENTENCE; do
SENTENCE=${SENTENCE//\'/\'\'} # escape single quotes for sqlite
cat << EOF | sqlite3 -init "" "$TRANSLATIONTARGETFILE"
$SQLITE_INIT

attach '$TRANSLATIONFILE' as tr;

INSERT OR IGNORE INTO translations (sentenceid, translation, probability)
SELECT $SENTENCEID, sentence, probability
FROM (
    SELECT sentence, probability, SUM(probability) OVER (ROWS UNBOUNDED PRECEDING) as cumu
    FROM (
        SELECT t.sentence, probability
        FROM sentences s
        JOIN direct_translations d ON d.sourceid = s.sentenceid
        JOIN sentences t ON t.sentenceid = d.targetid
        WHERE d.lang = '$TARGETLANG' AND s.sentence = '$SENTENCE' AND s.lang = '$SOURCELANG'
        ORDER BY probability DESC
    )
)
WHERE cumu - probability <= $MIN_COVERAGE;
EOF
done
MISSINNG_AFTER=$(missing-translations-count "$MODELFILE" "$TRANSLATIONTARGETFILE")
echo "  +$((MISSING_BEFORE - MISSINNG_AFTER)) => $(translation-coverage "$MODELFILE" "$TRANSLATIONTARGETFILE")"
}


add-indirect-translations() {
TRANSLATIONFILE=$1
NAME=$2
TARGETLANG=$3
MODELFILE=$4
TRANSLATIONTARGETFILE=$5

echo "  indirect translations from $NAME...";
MISSING_BEFORE=$(missing-translations-count "$MODELFILE" "$TRANSLATIONTARGETFILE")
missing-translations "$MODELFILE" "$TRANSLATIONTARGETFILE" | sponge | while read -r SENTENCEID SENTENCE; do
SENTENCE=${SENTENCE//\'/\'\'} # escape single quotes for sqlite
cat << EOF | sqlite3 -init "" "$TRANSLATIONTARGETFILE"
$SQLITE_INIT

attach '$TRANSLATIONFILE' as tr;

INSERT OR IGNORE INTO translations (sentenceid, translation, probability)
SELECT $SENTENCEID, sentence, prob
FROM (
    SELECT sentenceid, sentence, prob, SUM(prob) OVER (ROWS UNBOUNDED PRECEDING) as cumu
    FROM (
        SELECT ts.sentenceid, ts.sentence, sum(probability) as prob
        FROM sentences s
        JOIN indirect_translations_ungrouped t
            ON t.sourceid = s.sentenceid AND t.lang = '$TARGETLANG'
        JOIN sentences ts ON ts.sentenceid = t.targetid
        WHERE s.sentence = '$SENTENCE' AND s.lang = '$SOURCELANG'
        GROUP BY t.targetid
        HAVING COUNT(DISTINCT pivot_lang) >= 2
        ORDER BY prob DESC
    )
)
WHERE cumu - prob <= $MIN_COVERAGE
EOF
done
MISSINNG_AFTER=$(missing-translations-count "$MODELFILE" "$TRANSLATIONTARGETFILE")
echo "  +$((MISSING_BEFORE - MISSINNG_AFTER)) => $(translation-coverage "$MODELFILE" "$TRANSLATIONTARGETFILE")"
}


add-machine-translations-cache() {
TARGETLANG=$1
MODELFILE=$2
TRANSLATIONTARGETFILE=$3

echo "  machine translations from cache..."
MISSING_BEFORE=$(missing-translations-count "$MODELFILE" "$TRANSLATIONTARGETFILE")
if [ -s "$HOME/.cache/trans_cache.sqlite" ]; then
cat << EOF | sqlite3 -init "" "$TRANSLATIONTARGETFILE"
.bail on
attach '$MODELFILE' as m;
attach '$HOME/.cache/trans_cache.sqlite' as cache;

INSERT OR IGNORE INTO translations (sentenceid, translation, probability)
    WITH missing AS (
        SELECT s.sentenceid, s.sentence
        FROM m.sentences s
        LEFT OUTER JOIN translations t on s.sentenceid = t.sentenceid
        WHERE t.sentenceid IS NULL
        )
    SELECT s.sentenceid, t.translation, $MACHINE_PROBABILITY
    FROM missing s
    JOIN cache.translations t ON t.text = s.sentence
    WHERE t.sourcelang = '$SOURCELANG' AND t.targetlang = '$TARGETLANG';
EOF
fi
MISSINNG_AFTER=$(missing-translations-count "$MODELFILE" "$TRANSLATIONTARGETFILE")
echo "  +$((MISSING_BEFORE - MISSINNG_AFTER)) => $(translation-coverage "$MODELFILE" "$TRANSLATIONTARGETFILE")"
}


add-machine-translations-api() {
TARGETLANG=$1
MODELFILE=$2
TRANSLATIONTARGETFILE=$3

echo "  machine translations via api..."
MISSING_BEFORE=$(missing-translations-count "$MODELFILE" "$TRANSLATIONTARGETFILE")
missing-translations "$MODELFILE" "$TRANSLATIONTARGETFILE" | sponge | while read -r SENTENCEID SENTENCE; do
    TRANSLATED=$(./machine-translate.sh "$SOURCELANG" "$TARGETLANG" "$SENTENCE")
    if [ -n "$TRANSLATED" ]; then
        echo "    $SENTENCE -> '$TRANSLATED'"
        TRANSLATED_ESCAPED=$(echo "$TRANSLATED" | sed "s/'/''/g" | ./normalize_unicode.sh)
        sqlite3 -init "" "$TRANSLATIONTARGETFILE" "INSERT OR IGNORE INTO translations (sentenceid, translation, probability) VALUES ($SENTENCEID, '$TRANSLATED_ESCAPED', $MACHINE_PROBABILITY)"
        sleep 3
    else
        break # probably rate limiting issues
    fi
done || true
MISSINNG_AFTER=$(missing-translations-count "$MODELFILE" "$TRANSLATIONTARGETFILE")
echo "  +$((MISSING_BEFORE - MISSINNG_AFTER)) => $(translation-coverage "$MODELFILE" "$TRANSLATIONTARGETFILE")"
}




translation-coverage() {
    MODELFILE=$1
    TRANSLATIONTARGETFILE=$2
cat << EOF | sqlite3 -init "" "$TRANSLATIONTARGETFILE"
.mode tabs
attach '$MODELFILE' as m;
SELECT
    (SELECT CAST(COUNT(DISTINCT s.sentenceid) as real) FROM m.sentences s JOIN translations t on s.sentenceid = t.sentenceid)
    / (SELECT CAST(COUNT(*) as real) FROM m.sentences);
EOF
}


missing-translations-count() {
    MODELFILE=$1
    TRANSLATIONTARGETFILE=$2
cat << EOF | sqlite3 -init "" "$TRANSLATIONTARGETFILE"
.mode tabs
attach '$MODELFILE' as m;
SELECT COUNT(*)
FROM m.sentences s
LEFT OUTER JOIN translations t on s.sentenceid = t.sentenceid
WHERE t.sentenceid IS NULL;
EOF
}


missing-translations() {
    MODELFILE=$1
    TRANSLATIONTARGETFILE=$2
cat << EOF | sqlite3 -init "" "$TRANSLATIONTARGETFILE"
.mode tabs
attach '$MODELFILE' as m;
SELECT s.sentenceid, s.sentence
FROM m.sentences s
LEFT OUTER JOIN translations t on s.sentenceid = t.sentenceid
WHERE t.sentenceid IS NULL
ORDER BY s.coverage DESC;
EOF
}


finish-translationdb() {
TRANSLATIONTARGETFILE=$1
cat << EOF | sqlite3 -init "" "$TRANSLATIONTARGETFILE"
CREATE INDEX translations_sentenceid_idx ON translations (sentenceid);

SELECT "  optimize...";
ANALYZE;
PRAGMA optimize;
SELECT "  vacuum...";
VACUUM;
EOF
}

SQLITE_INIT=$(cat << EOF
.output /dev/null
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size=10000;
PRAGMA mmap_size = 30000000000;
.output
EOF
)

main "$@"; exit
