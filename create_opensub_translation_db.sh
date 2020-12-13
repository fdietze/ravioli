#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
#set -x # print all commands
shopt -s expand_aliases

main() {
# Optimizations
# faster sed alternative for cleanup: https://github.com/chmln/sd

LIMIT=${1-2000000}
MIN_OCCURRENCES=4
OUT="out"
TRANS_OUT="$OUT/translations_opensub"
mkdir -p $TRANS_OUT

# LANGUAGES=('fr' 'de' 'pt' 'it' 'ru')
LANGUAGES=('fr' 'de' 'pt' 'it' 'ru' 'es' 'en' 'nl' 'pl' 'ja' 'el')

# sort languages
IFS=$'\n' LANGUAGES=($(sort <<<"${LANGUAGES[*]}")); unset IFS

max=${#LANGUAGES[@]} # Take the length of that array
combinations=$((max*(max-1)/2))
SQLITEDB="$TRANS_OUT/translations$(printf "_%s" "${LANGUAGES[@]}")_${LIMIT}.sqlite"

echo "${LANGUAGES[*]}"
echo -e "Combinations: $combinations\n"

# download-corpora $LANGUAGES

echo -e "\n"
create-database-schema
echo -e "\n"

i=0
for ((idxA=0; idxA<max; idxA++)); do
    LANGA=${LANGUAGES[$idxA]}
    for ((idxB=idxA+1; idxB<max; idxB++)); do
        LANGB=${LANGUAGES[$idxB]}
        COMBO=$LANGA-$LANGB
        i=$((i+1))
        printf "%3d / %d (%s <-> %s)\n" $i $combinations $LANGA $LANGB
        import-corpus $LANGA $LANGB $COMBO $LIMIT $SQLITEDB
        echo -e "\n"
    done
    echo "$LANGA done."
    prune-sentences $LANGA $MIN_OCCURRENCES $SQLITEDB
    echo -e "\n\n"
done
finish $MIN_OCCURRENCES $SQLITEDB
ln -s --force "$(basename "$SQLITEDB")" "$TRANS_OUT/translations.sqlite"
}

download-corpora() {
LANGUAGES=$1
local max=${#LANGUAGES[@]} # Take the length of that array
i=0;
for ((idxA=0; idxA<max; idxA++)); do
    for ((idxB=idxA+1; idxB<max; idxB++)); do
        LANGA=${LANGUAGES[$idxA]}
        LANGB=${LANGUAGES[$idxB]}
        COMBO=$LANGA-$LANGB
        LANGA3=$(./iso639-1-to-3.py "$LANGA")
        LANGB3=$(./iso639-1-to-3.py "$LANGB")
        i=$((i+1))

        printf "%3d / %d (%s <-> %s) %s\n" $i $combinations $LANGA $LANGB "downloading parallel corpus..."
        (cd "$TRANS_OUT"; wget --continue --retry-on-host-error --tries=inf --no-verbose --show-progress "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/moses/$COMBO.txt.zip")

    done
done
}


create-database-schema() {
echo "Creating database schema..."
rm -f "$SQLITEDB"
cat << EOF | sqlite3 -init "" "$SQLITEDB"
.bail on
.output /dev/null
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA cache_size=10000;
.output

CREATE TABLE sentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY, -- alias for rowid, therefore autoincrementing
  lang TEXT NOT NULL,
  sentence TEXT NOT NULL,
  occurrences INTEGER NOT NULL DEFAULT 1,

  UNIQUE (sentence, lang)
);

-- speed up intermediate pruning
CREATE INDEX sentences_lang_occurrences_idx ON sentences (lang, occurrences);


CREATE TABLE links(
  sentenceid INTEGER NOT NULL,
  translationid INTEGER NOT NULL,
  occurrences INTEGER NOT NULL DEFAULT 1,

  PRIMARY KEY (sentenceid, translationid)
  FOREIGN KEY (sentenceid)
      REFERENCES sentences (sentenceid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
  FOREIGN KEY (translationid)
      REFERENCES sentences (sentenceid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
) WITHOUT ROWID;
-- speed up intermediate sentence pruning (links will be deleted using foreign key)
CREATE INDEX links_translationid_idx ON links (translationid);

EOF
}


extract-clean-sentences() {
COMBO=$1
LANG=$2

LANG3=$(./iso639-1-to-3.py "$LANG")
CLEANUP_COMMAND="./cleanup_default.sh"
if [ -f "cleanup_$LANG3.sh" ]; then
    CLEANUP_COMMAND="./cleanup_$LANG3.sh"
fi

unzip -p "$TRANS_OUT/$COMBO.txt.zip" "OpenSubtitles.$COMBO.$LANG" |
    ./normalize_unicode.sh |
    $CLEANUP_COMMAND |
    $CLEANUP_COMMAND  # cleanup twice is intentional (only once doesnt capture everything)
}


import-corpus() {
LANGA=$1
LANGB=$2
COMBO=$3
LIMIT=$4
SQLITEDB=$5

echo "importing sentence pairs into temporary db... (extraction, unicode normalization, cleanup)"
LANGA3=$(./iso639-1-to-3.py "$LANGA")
LANGB3=$(./iso639-1-to-3.py "$LANGB")
SQL_IMPORT=$(cat << EOF
.bail on
.output /dev/null
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size=10000;
PRAGMA mmap_size = 30000000000;
.output

CREATE TEMP TABLE rawpairs(
  sentence_a TEXT NOT NULL,
  sentence_b TEXT NOT NULL
);

.mode ascii
.separator "\t" "\n"
.import /dev/stdin rawpairs

SELECT "collecting sentences...";
INSERT INTO sentences (lang, sentence)
    SELECT '${LANGA3}', sentence_a FROM temp.rawpairs WHERE true -- without WHERE true: syntax error -> sqlite bug?
    ON CONFLICT (lang, sentence) DO UPDATE SET occurrences=occurrences+1;

INSERT INTO sentences (lang, sentence)
    SELECT '${LANGB3}', sentence_b FROM temp.rawpairs WHERE true
    ON CONFLICT (lang, sentence) DO UPDATE SET occurrences=occurrences+1;

SELECT "collecting links...";
INSERT INTO links (sentenceid, translationid)
    SELECT sa.sentenceid, sb.sentenceid
    FROM temp.rawpairs
    JOIN sentences sa ON sa.sentence = sentence_a AND sa.lang = '${LANGA3}'
    JOIN sentences sb ON sb.sentence = sentence_b AND sb.lang = '${LANGB3}'
    ON CONFLICT (sentenceid, translationid) DO UPDATE SET occurrences=occurrences+1;

SELECT "adding backlinks...";
INSERT INTO links (sentenceid, translationid)
    SELECT sb.sentenceid, sa.sentenceid
    FROM temp.rawpairs
    JOIN sentences sa ON sa.sentence = sentence_a AND sa.lang = '${LANGA3}'
    JOIN sentences sb ON sb.sentence = sentence_b AND sb.lang = '${LANGB3}'
    ON CONFLICT (sentenceid, translationid) DO UPDATE SET occurrences=occurrences+1;
EOF
)

(paste \
    <(extract-clean-sentences "$COMBO" "$LANGA") \
    <(extract-clean-sentences "$COMBO" "$LANGB") || true) |
    (rg '.+	.+' || true) | # remove lines where one side is empty
    head "-$LIMIT" |
    pv --line-mode -s "$LIMIT" |
    sqlite3 "$SQLITEDB" --init <(echo "$SQL_IMPORT")
}


prune-sentences() {
LANGA=$1
LANGA3=$(./iso639-1-to-3.py "$LANGA")
MIN_OCCURRENCES=$2
SQLITEDB=$3

cat << EOF | sqlite3 -init "" "$SQLITEDB"
.bail on
.output /dev/null
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size=10000;
PRAGMA mmap_size = 30000000000;
.output

SELECT "pruning low occurrence sentences in $LANGA (< $MIN_OCCURRENCES)...";
PRAGMA foreign_keys = ON;
DELETE FROM sentences WHERE lang = '$LANGA3' AND occurrences < $MIN_OCCURRENCES;
SELECT '-' || changes(*) || ' of ' || ((SELECT count(*) from sentences) + changes(*));
EOF
}


finish() {
MIN_OCCURRENCES=$1
SQLITEDB=$2
cat << EOF | sqlite3 -init "" "$SQLITEDB"
.bail on
.output /dev/null
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size=10000;
PRAGMA mmap_size = 30000000000;
PRAGMA automatic_index = false;
.output

SELECT "precomputing sentence degrees...";
ALTER TABLE sentences ADD COLUMN degree INTEGER NOT NULL DEFAULT 1;
UPDATE sentences
SET degree = (SELECT sum(occurrences) FROM links l WHERE l.sentenceid = sentences.sentenceid group by l.sentenceid)
WHERE sentenceid IN (SELECT sentenceid FROM links);

SELECT "precomputing sentence degrees per language...";
create TABLE lang_degree(
    sentenceid INTEGER NOT NULL,
    lang TEXT NOT NULL,
    degree INTEGER NOT NULL,

    PRIMARY KEY(sentenceid, lang)
);

INSERT INTO lang_degree(sentenceid, lang, degree)
SELECT l.sentenceid, t.lang, sum(l.occurrences)
FROM links l
JOIN sentences t ON t.sentenceid = l.translationid
GROUP BY l.sentenceid, t.lang;

SELECT "precomputing second-level sentence degrees per language...";
create TABLE lang_degree2(
    sentenceid INTEGER NOT NULL,
    lang TEXT NOT NULL,
    degree2 INTEGER NOT NULL,

    PRIMARY KEY(sentenceid, lang)
);

.output /dev/null
PRAGMA temp_store = FILE; -- have temporary table on-disk, because it might be too big for memory
.output
INSERT INTO lang_degree2(sentenceid, lang, degree2)
SELECT l.sentenceid, d2.lang, sum(l.occurrences*d2.degree) AS degree2
FROM links l
JOIN lang_degree d2 ON d2.sentenceid = l.translationid
GROUP BY l.sentenceid, d2.lang
;

SELECT "dropping temporary indexes...";
DROP INDEX sentences_lang_occurrences_idx;
DROP INDEX links_translationid_idx;
SELECT "creating indexes...";
CREATE INDEX sentences_lang_sentenceid_idx ON sentences(lang, sentenceid DESC); -- suggested by .expert


CREATE VIEW direct_translations AS
    SELECT s.sentenceid as sourceid, t.lang, ts.sentenceid targetid, CAST(l.occurrences as real)/t.degree as probability
    FROM sentences s
    JOIN links l ON l.sentenceid = s.sentenceid
    JOIN sentences ts ON ts.sentenceid = l.translationid
    JOIN lang_degree t ON t.sentenceid = s.sentenceid AND ts.lang = t.lang;

CREATE VIEW chain2 AS
    select l1.sentenceid, l1.translationid as l1_translationid, l1.occurrences as l1_occurrences, l2.translationid as l2_translationid, l2.occurrences as l2_occurrences from links l1 JOIN links l2 ON l2.sentenceid = l1.translationid;

CREATE VIEW chain2_acyclic AS
    select * FROM chain2 l WHERE l.sentenceid != l.l2_translationid;

CREATE VIEW indirect_translations_ungrouped AS
    SELECT
        l.sentenceid as sourceid,
        sp.lang as pivot_lang,
        st.lang as lang,
        st.sentenceid as targetid,
        CAST(l.l1_occurrences * l.l2_occurrences as real)/d2.degree2 as probability
    FROM chain2_acyclic l
    JOIN sentences sp  ON sp.sentenceid  = l.l1_translationid
    JOIN sentences st ON st.sentenceid = l.l2_translationid
    JOIN lang_degree2 d2 ON d2.sentenceid = sourceid AND d2.lang = st.lang;
EOF

cat << EOF | sqlite3 -init "" "$SQLITEDB"
.headers off
SELECT "analyze & optimize...";
ANALYZE;
PRAGMA optimize;
SELECT "vacuum...";
VACUUM;
EOF
}

main "$@"; exit
