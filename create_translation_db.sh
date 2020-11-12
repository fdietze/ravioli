#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
# set -x # print all commands
shopt -s expand_aliases


OUT="out"
TRANS_OUT="$OUT/translations"
mkdir -p $TRANS_OUT

# https://tatoeba.org (Multilingual collaborative sentence translation database)
# https://tatoeba.org/eng/downloads
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/sentences_detailed.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/links.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/tags.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/sentences_with_audio.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/user_languages.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/users_sentences.csv")

echo "extracting and normalizing unicode..."
[ -s "$TRANS_OUT/sentences.tsv" ] || (tar xOjf "$TRANS_OUT/sentences_detailed.tar.bz2" sentences_detailed.csv | ./normalize_unicode.sh > "$TRANS_OUT/sentences.tsv")
[ -s "$TRANS_OUT/links.tsv" ] || (tar xOjf "$TRANS_OUT/links.tar.bz2" links.csv > "$TRANS_OUT/links.tsv")
[ -s "$TRANS_OUT/tags.tsv" ] || (tar xOjf "$TRANS_OUT/tags.tar.bz2" tags.csv > "$TRANS_OUT/tags.tsv")
[ -s "$TRANS_OUT/sentences_with_audio.tsv" ] || (tar xOjf "$TRANS_OUT/sentences_with_audio.tar.bz2" sentences_with_audio.csv > "$TRANS_OUT/sentences_with_audio.tsv")
[ -s "$TRANS_OUT/user_languages.tsv" ] || (tar xOjf "$TRANS_OUT/user_languages.tar.bz2" user_languages.csv > "$TRANS_OUT/user_languages.tsv")
# [ -s "$TRANS_OUT/users_sentences.tsv" ] || (tar xOjf "$TRANS_OUT/users_sentences.tar.bz2" users_sentences.csv > "$TRANS_OUT/users_sentences.tsv")

SQLITEDB="$TRANS_OUT/translations.sqlite"


if [ ! -s "$TRANS_OUT/translations.sqlite" ]; then
echo "Creating translation database..."
# some sentences referenced by links might be invalid. That's ok, because some sentences were deduplicated, for example https://tatoeba.org/eng/sentences/show/3094
# after normalization, there will be duplicated sentences in the database: https://github.com/Tatoeba/tatoeba2/issues/1970
rm -f "$SQLITEDB"
cat << EOF | sqlite3 -init "" "$SQLITEDB"

.bail on
PRAGMA foreign_keys = ON;


SELECT "importing all sentences...";
CREATE TABLE sentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  lang TEXT NOT NULL,
  sentence TEXT NOT NULL,
  username TEXT NOT NULL,
  date_added TEXT NOT NULL,
  date_modified TEXT NOT NULL
);
CREATE INDEX sentences_lang_idx ON sentences (lang);
CREATE INDEX sentences_sentence_idx ON sentences (sentence);
CREATE INDEX sentences_username_idx ON sentences (username);
.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/sentences.tsv' sentences
EOF


# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
PRAGMA foreign_keys = ON;

SELECT "importing all links...";
CREATE TABLE links(
  sentenceid INTEGER NOT NULL,
  translationid INTEGER NOT NULL,

  PRIMARY KEY (sentenceid, translationid)
  FOREIGN KEY (sentenceid)
      REFERENCES sentences (sentenceid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
  FOREIGN KEY (translationid)
      REFERENCES sentences (sentenceid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
);

CREATE INDEX links_sentenceid_idx ON links (sentenceid);
CREATE INDEX links_translationid_idx ON links (translationid);
.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/links.tsv' links
EOF


# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
PRAGMA foreign_keys = ON;

SELECT "importing all tags...";
CREATE TABLE tags(
  sentenceid INTEGER NOT NULL,
  tag TEXT NOT NULL,

  PRIMARY KEY (sentenceid, tag)
  FOREIGN KEY (sentenceid)
      REFERENCES sentences (sentenceid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
);

CREATE INDEX tags_sentenceid_idx ON tags (sentenceid);
CREATE INDEX tags_tag_idx ON tags (tag);
.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/tags.tsv' tags
EOF


# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
PRAGMA foreign_keys = ON;

SELECT "importing all sentences_with_audio...";
CREATE TABLE sentences_with_audio(
  sentenceid INTEGER NOT NULL,
  username TEXT NOT NULL,
  license TEXT NOT NULL,
  attribution_url TEXT NOT NULL,

  FOREIGN KEY (sentenceid)
      REFERENCES sentences (sentenceid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
);

CREATE INDEX sentences_with_audio_sentenceid_idx ON sentences_with_audio (sentenceid);
CREATE INDEX sentences_with_audio_username_idx ON sentences_with_audio (username);
CREATE INDEX sentences_with_audio_license_idx ON sentences_with_audio (license);
.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/sentences_with_audio.tsv' sentences_with_audio
EOF


# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
PRAGMA foreign_keys = ON;

SELECT "importing all user_languages...";
CREATE TABLE user_languages(
  lang TEXT NOT NULL,
  skill_level INTEGER NOT NULL,
  username TEXT NOT NULL,
  details TEXT
);

CREATE INDEX user_languages_lang_idx ON user_languages (lang);
CREATE INDEX user_languages_skill_level_idx ON user_languages (skill_level);
CREATE INDEX user_languages_username_idx ON user_languages (username);
.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/user_languages.tsv' user_languages
EOF


cat << EOF | sqlite3 -init "" "$SQLITEDB"
.bail on
PRAGMA foreign_keys = ON;

-- some backlinks are missing...
-- https://github.com/Tatoeba/tatoeba2/issues/2579
SELECT "Ensuring all backlinks are there...";
INSERT OR IGNORE INTO links (sentenceid, translationid) SELECT translationid, sentenceid FROM links;

.headers off
SELECT "vacuum...";
VACUUM;

SELECT "checking database integrity...";
PRAGMA integrity_check;
EOF

ls -lh $SQLITEDB
fi


# attach 'out/translations/translations.sqlite' as tr;
# attach 'out/fr_100000/model.sqlite' as m;
# select s.sentenceid, trs2.sentence from m.sentences s JOIN tr.sentences trs ON s.sentence = trs.sentence AND trs.lang='fra' JOIN tr.links l ON l.sentenceid = trs.sentenceid JOIN tr.sentences trs2 ON trs2.sentenceid = l.translationid AND trs2.lang = 'deu' GROUP BY s.sentenceid, trs2.sentence order by occurrences DESC LIMIT 100;

# translate single sentence
# select * from sentences s JOIN links l ON s.sentenceid = l.sentenceid JOIN sentences s2 ON s2.sentenceid = l.translationid where s.:sqlite> select * from sentences s JOIN links l ON s.sentenceid = l.sentenceid JOIN sentences s2 ON s2.sentenceid = l.translationid where s.sentence='D''accord.' and s2.lang = 'deu' limit 10;

# show corpus sentences where no sentences are found
# select s.occurrences, s.sentence, COUNT(trs.sentenceid) c from m.sentences s LEFT OUTER JOIN tr.sentences trs ON s.sentence = trs.sentence GROUP BY s.sentenceid HAVING c = 0 order by occurrences DESC LIMIT 100;
