#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
# set -x # print all commands
shopt -s expand_aliases


OUT="out"
TRANS_OUT="$OUT/translations"
mkdir -p $TRANS_OUT

SQLITEDB="$TRANS_OUT/translations.sqlite"
if [ ! -s "$TRANS_OUT/translations.sqlite" ]; then
# https://tatoeba.org (Multilingual collaborative sentence translation database)
# https://tatoeba.org/eng/downloads
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/sentences_detailed.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/links.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/tags.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/sentences_with_audio.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/user_languages.tar.bz2")
(cd "$TRANS_OUT"; wget --no-verbose --show-progress --timestamping "https://downloads.tatoeba.org/exports/users_sentences.csv")


echo "extracting and normalizing unicode..."
(tar xOjf "$TRANS_OUT/sentences_detailed.tar.bz2" sentences_detailed.csv | ./normalize_unicode.sh > "$TRANS_OUT/sentences.tsv")
(tar xOjf "$TRANS_OUT/links.tar.bz2" links.csv > "$TRANS_OUT/links.tsv")
(tar xOjf "$TRANS_OUT/tags.tar.bz2" tags.csv > "$TRANS_OUT/tags.tsv")
(tar xOjf "$TRANS_OUT/sentences_with_audio.tar.bz2" sentences_with_audio.csv > "$TRANS_OUT/sentences_with_audio.tsv")
(tar xOjf "$TRANS_OUT/user_languages.tar.bz2" user_languages.csv > "$TRANS_OUT/user_languages.tsv")
# [ -s "$TRANS_OUT/users_sentences.tsv" ] || (tar xOjf "$TRANS_OUT/users_sentences.tar.bz2" users_sentences.csv > "$TRANS_OUT/users_sentences.tsv")


echo "Creating translation database..."
# some sentences referenced by links might be invalid. That's ok, because some sentences were deduplicated, for example https://tatoeba.org/eng/sentences/show/3094
# after normalization, there will be duplicated sentences in the database: https://github.com/Tatoeba/tatoeba2/issues/1970
rm -f "$SQLITEDB"
cat << EOF | sqlite3 -init "" "$SQLITEDB"

.bail on
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = MEMORY;
PRAGMA synchronous = OFF;

SELECT "importing all sentences...";
CREATE TABLE sentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  lang TEXT NOT NULL,
  sentence TEXT NOT NULL,
  username TEXT NOT NULL,
  date_added TEXT NOT NULL,
  date_modified TEXT NOT NULL
);

.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/sentences.tsv' sentences

CREATE INDEX sentences_lang_idx ON sentences (lang);
CREATE INDEX sentences_sentence_idx ON sentences (sentence);
CREATE INDEX sentences_sentence_lang_idx ON sentences (sentence,lang);
CREATE INDEX sentences_sentenceid_lang_idx ON sentences (sentenceid,lang);
CREATE INDEX sentences_username_idx ON sentences (username);
EOF


# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = MEMORY;
PRAGMA synchronous = OFF;

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

.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/links.tsv' links

CREATE INDEX links_sentenceid_idx ON links (sentenceid);
CREATE INDEX links_translationid_idx ON links (translationid);
EOF


# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = MEMORY;
PRAGMA synchronous = OFF;

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

.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/tags.tsv' tags

CREATE INDEX tags_sentenceid_idx ON tags (sentenceid);
CREATE INDEX tags_tag_idx ON tags (tag);
EOF


# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = MEMORY;
PRAGMA synchronous = OFF;

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

.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/sentences_with_audio.tsv' sentences_with_audio

CREATE INDEX sentences_with_audio_sentenceid_idx ON sentences_with_audio (sentenceid);
CREATE INDEX sentences_with_audio_username_idx ON sentences_with_audio (username);
CREATE INDEX sentences_with_audio_license_idx ON sentences_with_audio (license);
EOF


# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = MEMORY;
PRAGMA synchronous = OFF;

SELECT "importing all user_languages...";
CREATE TABLE user_languages(
  lang TEXT NOT NULL,
  skill_level INTEGER NOT NULL,
  username TEXT NOT NULL,
  details TEXT
);

.mode ascii
.separator "\t" "\n"
.import '$TRANS_OUT/user_languages.tsv' user_languages

CREATE INDEX user_languages_lang_idx ON user_languages (lang);
CREATE INDEX user_languages_skill_level_idx ON user_languages (skill_level);
CREATE INDEX user_languages_username_idx ON user_languages (username);
EOF


cat << EOF | sqlite3 -init "" "$SQLITEDB"
.bail on
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = MEMORY;
PRAGMA synchronous = OFF;

-- some backlinks are missing...
-- https://github.com/Tatoeba/tatoeba2/issues/2579
SELECT "Ensuring all backlinks are there...";
INSERT OR IGNORE INTO links (sentenceid, translationid) SELECT translationid, sentenceid FROM links;


SELECT "Deduplicating sentences...";
-- There will be duplicates, because of improper unicode normalization: https://github.com/Tatoeba/tatoeba2/issues/1970
-- finding duplicates:
-- WITH duplicates as (select min(sentenceid) as minid, sentence from sentences group by sentence,lang having count(*) > 1) SELECT sentenceid as duplicate, duplicates.minid as original FROM duplicates JOIN sentences s ON s.sentence = duplicates.sentence WHERE duplicate != original LIMIT 10;

SELECT "  links...";
INSERT OR IGNORE INTO links (sentenceid, translationid) WITH duplicates as (select min(sentenceid) as minid, sentence from sentences group by sentence,lang having count(*) > 1) SELECT duplicates.minid as sentenceid, l.translationid FROM duplicates JOIN sentences s ON s.sentence = duplicates.sentence JOIN links l ON l.sentenceid = s.sentenceid WHERE s.sentenceid != duplicates.minid;

SELECT "  tags...";
INSERT OR IGNORE INTO tags (sentenceid, tag) WITH duplicates as (select min(sentenceid) as minid, sentence from sentences group by sentence,lang having count(*) > 1) SELECT duplicates.minid as sentenceid, t.tag FROM duplicates JOIN sentences s ON s.sentence = duplicates.sentence JOIN tags t ON t.sentenceid = s.sentenceid WHERE s.sentenceid != duplicates.minid;

SELECT "  sentences_with_audio...";
INSERT OR IGNORE INTO sentences_with_audio (sentenceid, username, license, attribution_url) WITH duplicates as (select min(sentenceid) as minid, sentence from sentences group by sentence,lang having count(*) > 1) SELECT duplicates.minid as sentenceid, a.username, a.license, a.attribution_url FROM duplicates JOIN sentences s ON s.sentence = duplicates.sentence JOIN sentences_with_audio a ON a.sentenceid = s.sentenceid WHERE s.sentenceid != duplicates.minid;

SELECT "  deleting duplicate sentences...";
DELETE FROM sentences WHERE sentenceid IN (WITH duplicates as (select min(sentenceid) as minid, sentence from sentences group by sentence,lang having count(*) > 1) SELECT sentenceid FROM duplicates JOIN sentences s ON s.sentence = duplicates.sentence WHERE sentenceid != duplicates.minid);



.headers off
SELECT "vacuum...";
VACUUM;

SELECT "checking database integrity...";
PRAGMA integrity_check;
EOF

ls -lh $SQLITEDB
fi
