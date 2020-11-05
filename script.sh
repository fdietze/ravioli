#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
set -x # print all commands
shopt -s expand_aliases



LANG=${1-"de"}
CORPUS_SENTENCE_LIMIT=${2-1000000}
COUNT_THRESHOLD=$(( "$CORPUS_SENTENCE_LIMIT" / 2000 ))
OUT="out"
CORPUS_OUT="out/${LANG}_${CORPUS_SENTENCE_LIMIT}"
mkdir -p "$OUT"
mkdir -p "$CORPUS_OUT"


docker build docker -t ravioli

alias in_docker='docker run -i --mount type=bind,source="$(pwd)",target="/home/lamachine" ravioli:latest'
alias colibri-patternmodeller='in_docker colibri-patternmodeller'
alias colibri-classencode='in_docker colibri-classencode'

in_docker gcc -g -fPIC -shared extension-functions.c -o extension-functions.so


if [ ! -s "$OUT/${LANG}_subtitles.txt" ]; then
    wget -c "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/mono/$LANG.txt.gz" -O "$OUT/$LANG.txt.gz"

    echo "extracting..."
    pv "$OUT/$LANG.txt.gz" | gzip -d | cat > "$OUT/${LANG}_subtitles.txt"
fi


if [ ! -s "$CORPUS_OUT/sentences.txt" ]; then
    CLEANUP_COMMAND="./cleanup_default.sh"
    if [ -f "cleanup_$LANG.sh" ]; then
        CLEANUP_COMMAND="./cleanup_$LANG.sh"
    fi
    (
    pv "$OUT/${LANG}_subtitles.txt" |
        $CLEANUP_COMMAND |
        $CLEANUP_COMMAND | # cleanup twice is intentional (only once doesn't capture everything)
        in_docker ./sentences_stanza.py "$LANG" |
        head -"$CORPUS_SENTENCE_LIMIT" |
        cat > "$CORPUS_OUT/sentences.txt"
    ) || true # piping through docker/python makes problems
fi

if [ ! -s "$CORPUS_OUT/tokens.txt" ]; then
    (
    pv "$CORPUS_OUT/sentences.txt" |
        in_docker ./tokenize_stanza.py "$LANG" |
        cat > "$CORPUS_OUT/tokens.txt"
            ) || true # piping through/python docker makes problems
fi


# TODO: list all non-alpha characters: awk -vFS="" '{for(i=1;i<=NF;i++){ if($i~/[^a-zA-Z0-9]/) { w[$i]++} } }END{asorti(w, sorted); for(i in sorted) print sorted[i],w[sorted[i]]}' subtitles_fr_sentences.txt
# TODO: sentences starting with: '<space>, where ' is not used as apostroph
# TODO: Same spelling, but without accents: 'Ca va'
# TODO: remove duplicate movies, e.g. search in de: "Glauben Sie, wer anders"
# TODO: UCTO tool to split sentences. Separate words from beginnings and endings? echo -e "   Halllo du wurst? Denkste. \n bla" | ucto -l -L de -P -n
# TODO: colibri case sensitivity?
# Failli] ?
# [UNCUT]
# (N'attendez-vous de moi ?
# Il y en a tellement-- ((La Magra is coming !
# Récupérer ce pouvoir{*puissance*} sur !

# TODO: keep original list of sentences intact, but tokenize, lowercase etc for ngram detection. Since the reverse index points to sentence indices, it also points to the original sentences.


export CORPUS="$CORPUS_OUT/${LANG}_tokens" # $CORPUS.txt
DIR="$CORPUS_OUT"

echo "### Encoding $CORPUS.txt ..."
cat -n "$DIR/sentences.txt" | paste - "$DIR/tokens.txt" | sed 's/"/\\"/g' > "$DIR/sentences.tsv"
colibri-classencode "$DIR/tokens.txt" -d "$DIR/"
echo -e "\n"

echo "### Creating n-grams count model..."
colibri-patternmodeller --datafile "$DIR/tokens.colibri.dat" --classfile "$DIR/tokens.colibri.cls" --threshold $COUNT_THRESHOLD --skipgrams --flexgrams S --outputmodel "$DIR/tokens.colibri.indexedpatternmodel"
echo -e "\n"

echo "### Extracting n-gram details from model..."
# 1:PATTERN 2:COUNT 3:_ 4:TOKENS 5:COVERAGE 6:CATEGORY 7:SIZE 8:FREQUENCY 9:REFERENCES
colibri-patternmodeller --inputmodel "$DIR/tokens.colibri.indexedpatternmodel" --classfile "$DIR/tokens.colibri.cls" -P 2> /dev/null | tail -n +2 | cut -f1,5,7,8 -d $'\t' | LC_ALL=C sort -k2gr -t $'\t' 1> "$DIR/tokens.patterns.txt"
cat -n "$DIR/tokens.patterns.txt" | sed 's/"/\\"/g' > "$DIR/tokens.patterns.tsv"
head -50 "$DIR/tokens.patterns.txt"
echo -e "\n"

echo "### Creating reverse-index..."
# colibri-patternmodeller --inputmodel $DIR/tokens.colibri.indexedpatternmodel --classfile $DIR/tokens.colibri.cls --datafile $DIR/tokens.colibri.dat --printreverseindex | head -n -1 | sed 's/"/\\"/g' | awk -v FS=$'\t' -v OFS=$'\t' '{split($1, sentenceId, ":"); print sentenceId[1], sentenceId[2], $2; }' > $DIR/tokens.reverse-index.tsv

# TODO: remove sentences which contain untracked patterns
colibri-patternmodeller --inputmodel "$DIR/tokens.colibri.indexedpatternmodel" --classfile "$DIR/tokens.colibri.cls" -P 2> /dev/null | tail -n +2 | sed 's/"/\\"/g' | awk -v FS=$'\t' -v OFS=$'\t' '{split($9, positions, " "); for(pos in positions) { split(positions[pos], senpos, ":"); print senpos[1], senpos[2], $1 }}' 1> "$DIR/tokens.reverse-index.tsv"
echo -e "\n"


echo "### creating sqlite database"
./import-data-sqlite.sh "$DIR/model.sqlite" "$DIR/sentences.tsv" "$DIR/tokens.patterns.tsv" "$DIR/tokens.reverse-index.tsv" || true
echo -e "\n"
