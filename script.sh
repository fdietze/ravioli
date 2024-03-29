#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
# set -x # print all commands
shopt -s expand_aliases

# http://opus.nlpl.eu/opusapi

LANG=${1:-"fra"}
LANG2=$(./iso639-3-to-1.py "$LANG")

CORPUS_SENTENCE_LIMIT=${2:-3000000}
COUNT_THRESHOLD=$(( "$CORPUS_SENTENCE_LIMIT" / 10000 ))
COUNT_THRESHOLD=$(( COUNT_THRESHOLD >= 3 ? COUNT_THRESHOLD : 3 ))
COUNT_THRESHOLD=$(( COUNT_THRESHOLD <= 500 ? COUNT_THRESHOLD : 500 ))

MAX_SENTENCE_LENGTH=120

OUT="out"
CORPUS="${LANG}_${CORPUS_SENTENCE_LIMIT}"
CORPUS_OUT="$OUT/$CORPUS"
mkdir -p "$CORPUS_OUT"



if [ ! -s "$OUT/${LANG}.txt" ]; then
    echo "Downloading corpus..."
    wget --continue --no-verbose --show-progress "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/mono/$LANG2.txt.gz" -O "$OUT/$LANG.txt.gz"

    echo "Extracting..."
    pv "$OUT/$LANG.txt.gz" | gzip -d > "$OUT/${LANG}.txt"
fi


echo "Normalizing unicode, cleaning up, extracting sentences..."
CLEANUP_COMMAND="./cleanup_default.sh"
if [ -f "cleanup_$LANG.sh" ]; then
    CLEANUP_COMMAND="./cleanup_$LANG.sh"
fi
PRUNE_COMMAND="./prune_default.sh"
if [ -f "prune_$LANG.sh" ]; then
    PRUNE_COMMAND="./prune_$LANG.sh"
fi
(
cat "$OUT/${LANG}.txt" |
    ./normalize_unicode.sh |
    $CLEANUP_COMMAND |
    $PRUNE_COMMAND |
    $CLEANUP_COMMAND | # cleanup twice is intentional (only once might not capture everything)
    $PRUNE_COMMAND |
    awk '{ if (length($0) < '"$MAX_SENTENCE_LENGTH"') print }' |
    # ./sentences_stanza.py "$LANG2" |
    pv --line-mode -s "$CORPUS_SENTENCE_LIMIT" |
    head -"$CORPUS_SENTENCE_LIMIT" |
    cat > "$CORPUS_OUT/sentences.txt"
) || true # piping through python makes problems





echo "Tokenization...."
cat "$CORPUS_OUT/sentences.txt" |
    sacremoses --quiet --processes 8 -l "$LANG2" tokenize --xml-escape |
    # pv --line-mode -s "$(wc -l "$CORPUS_OUT/sentences.txt" | cut -f1 -d " ")" |
    cat > "$CORPUS_OUT/tokens.txt"


# TODO: sentences starting with: '<space>, where ' is not used as apostroph
# TODO: Same spelling, but without accents: 'Ca va'
# TODO: remove duplicate movies, e.g. search in de: "Glauben Sie, wer anders"


DIR="$CORPUS_OUT"

echo "Encoding $DIR/sentences.txt ..."
cat -n "$DIR/sentences.txt" | paste - "$DIR/tokens.txt" | sed 's/"/\\"/g' > "$DIR/sentences.tsv"
colibri-classencode "$DIR/tokens.txt" -d "$DIR/"

echo "Creating n-grams count model (Threshold: $COUNT_THRESHOLD)..."
colibri-patternmodeller --datafile "$DIR/tokens.colibri.dat" --classfile "$DIR/tokens.colibri.cls" --threshold $COUNT_THRESHOLD --skipgrams --flexgrams S --outputmodel "$DIR/tokens.colibri.indexedpatternmodel"

echo "Extracting n-gram patterns from model..."
# 1:PATTERN 2:COUNT 3:_ 4:TOKENS 5:COVERAGE 6:CATEGORY 7:SIZE 8:FREQUENCY 9:REFERENCES
colibri-patternmodeller --inputmodel "$DIR/tokens.colibri.indexedpatternmodel" --classfile "$DIR/tokens.colibri.cls" -P 2> /dev/null | tail -n +2 | cut -f1,5 -d $'\t' | LC_ALL=C sort -k2gr -t $'\t' 1> "$DIR/tokens.patterns.txt"
cat -n "$DIR/tokens.patterns.txt" | sed 's/"/\\"/g' > "$DIR/tokens.patterns.tsv"
head -50 "$DIR/tokens.patterns.txt"

echo "Creating reverse-index..."
# colibri-patternmodeller --inputmodel $DIR/tokens.colibri.indexedpatternmodel --classfile $DIR/tokens.colibri.cls --datafile $DIR/tokens.colibri.dat --printreverseindex | head -n -1 | sed 's/"/\\"/g' | awk -v FS=$'\t' -v OFS=$'\t' '{split($1, sentenceId, ":"); print sentenceId[1], sentenceId[2], $2; }' > $DIR/tokens.reverse-index.tsv

# TODO: remove sentences which contain untracked patterns
colibri-patternmodeller --inputmodel "$DIR/tokens.colibri.indexedpatternmodel" --classfile "$DIR/tokens.colibri.cls" -P 2> /dev/null | tail -n +2 | sed 's/"/\\"/g' | awk -v FS=$'\t' -v OFS=$'\t' '{split($9, positions, " "); for(pos in positions) { split(positions[pos], senpos, ":"); print senpos[1], senpos[2], $1 }}' 1> "$DIR/tokens.reverse-index.tsv"


echo "Creating sqlite database"
./import-data-sqlite.sh "$DIR/${LANG}_model.sqlite" "$DIR/sentences.tsv" "$DIR/tokens.patterns.tsv" "$DIR/tokens.reverse-index.tsv" "$LANG" || true


echo "translating model"
./translate_model.sh "$CORPUS" "$LANG"

echo "copying to ui/public"
rm -f ravioli-ui/public/languages/"${LANG}"*
cp "$DIR"/*.sqlite ravioli-ui/public/languages/
ls -lh ravioli-ui/public/languages/"${LANG}"*
