#!/usr/bin/env bash
set -e # exit when one command fails

# docker pull proycon/lamachine:latest && docker run -p 8080:80 -t -i --mount type=bind,source=$(pwd),target="/home/lamachine/ravioli" proycon/lamachine:latest
# sudo apt install sqlite3 libsqlite3-dev
# gcc -g -fPIC -shared extension-functions.c -o extension-functions.so

# https://wortschatz.uni-leipzig.de/en/download/french
# https://ielanguages.com/blog/free-corpora-of-spoken-french/
# curl https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/mono/de.txt.gz | gzip -d > subtitles_de.txt

#cat fra_mixed_2009_100K-sentences.txt | cut -f2- | sort -u | shuf > fra_sentences.txt
# cat fra_mixed-typical_2012_1M-sentences.txt | cut -f2- | sort -u | shuf > fra_sentences.txt
# sort -u subtitles.txt | shuf | head -100000 > subtitles_100k.txt
# cat subtitles_de.txt | grep -v '\.\.\.$' | grep -v '^[\.\!\?0-9]*$' | grep -v '[\-\:\"]' | sed 's/^- //' | grep '[\.?!]$' | sed 's/\s*\([\.!?]\)/\1/' > subtitles_de_sentences.txt
# todo: leading hash sign

# cat subtitles_de.txt |
#     grep '[\.?!]$' |
#     grep -v '^[\.\!\?0-9]*$' |
#     grep -v '\.\.\.' |
#     grep -v '[\-\:\"#]' |
#     sed 's/^-\s*//' |
#     sed 's/\s*\([\.!?]\)$/\1/' |
#     sed 's/(.*)\s*//' |
#     head -200000 > subtitles_de_sentences.txt


# cat subtitles_fr.txt |
#     grep '[\.?!]$' |
#     grep -v '^[\.\!\?0-9]*$' |
#     grep -v '\.\.\.' |
#     grep -v '[\-\:\"#]' |
#     sed 's/^-\s*//' |
#     sed 's/\s*\([!?]\)$/ \1/' | # french convention to have a space before ? and !
#     sed 's/\s*\([\.]\)$/\1/' |
#     sed 's/(.*)\s*//' |
#     head -200000 > subtitles_fr_sentences.txt


export CORPUS=$1 # $CORPUS.txt
COUNT_THRESHOLD=10

rm -rf $CORPUS
mkdir -p $CORPUS

echo "### Encoding $CORPUS.txt ..."
colibri-classencode $CORPUS.txt -d "$CORPUS/"
cat -n $CORPUS.txt | sed 's/"/\\"/g' > $CORPUS/$CORPUS.tsv
echo -e "\n"

echo "### Creating n-grams count model..."
colibri-patternmodeller --datafile $CORPUS/$CORPUS.colibri.dat --classfile $CORPUS/$CORPUS.colibri.cls --threshold $COUNT_THRESHOLD --skipgrams --flexgrams S --outputmodel $CORPUS/$CORPUS.colibri.indexedpatternmodel
echo -e "\n"

echo "### Extracting n-gram details from model..."
# 1:PATTERN 2:COUNT 3:_ 4:TOKENS 5:COVERAGE 6:CATEGORY 7:SIZE 8:FREQUENCY 9:REFERENCES
colibri-patternmodeller --inputmodel $CORPUS/$CORPUS.colibri.indexedpatternmodel --classfile $CORPUS/$CORPUS.colibri.cls -P | tail -n +2 | cut -f1,5,7,8 -d $'\t' | LC_ALL=C sort -k2gr -t $'\t' > $CORPUS/$CORPUS.patterns.txt
cat -n $CORPUS/$CORPUS.patterns.txt | sed 's/"/\\"/g' > $CORPUS/$CORPUS.patterns.tsv
head -50 $CORPUS/$CORPUS.patterns.txt
echo -e "\n"

echo "### Creating reverse-index..."
colibri-patternmodeller --inputmodel $CORPUS/$CORPUS.colibri.indexedpatternmodel --classfile $CORPUS/$CORPUS.colibri.cls --datafile $CORPUS/$CORPUS.colibri.dat --printreverseindex | head -n -1 | sed 's/"/\\"/g' | awk -v FS=$'\t' -v OFS=$'\t' '{split($1, sentenceId, ":"); print sentenceId[1], sentenceId[2], $2; }' > $CORPUS/$CORPUS.reverse-index.tsv
echo -e "\n"


echo "### creating sqlite database"
./import-data-sqlite.sh $CORPUS || true
echo -e "\n"

echo "### Listing best sentences..."
./best-sentences.sh $CORPUS
