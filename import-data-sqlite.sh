#!/usr/bin/env bash

CORPUS=$1

rm -f $CORPUS/$CORPUS.sqlite
cat << EOF | sqlite3 $CORPUS/$CORPUS.sqlite
PRAGMA foreign_keys = ON;

CREATE TABLE sentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  sentence TEXT NOT NULL UNIQUE ON CONFLICT IGNORE
);

CREATE TABLE patterns(
  rank INTEGER NOT NULL,
  pattern TEXT NOT NULL PRIMARY KEY,
  coverage REAL NOT NULL,
  size INTEGER NOT NULL,
  frequency REAL NOT NULL
);

CREATE TABLE reverseindex(
    sentenceid INTEGER NOT NULL,
    position INTEGER NOT NULL,
    pattern TEXT NOT NULL,

    PRIMARY KEY (sentenceid, position)
    FOREIGN KEY (sentenceid)
        REFERENCES sentences (sentenceid)
        ON UPDATE CASCADE
        ON DELETE CASCADE
    FOREIGN KEY (pattern)
        REFERENCES patterns (pattern)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);
CREATE INDEX reverseindex_sentenceid_idx ON reverseindex (sentenceid);
CREATE INDEX reverseindex_position_idx ON reverseindex (position);
CREATE INDEX reverseindex_pattern_idx ON reverseindex (pattern);

# insert empty pattern to fulfill foreign key constraint
INSERT INTO "patterns"(rank,pattern,coverage,size,frequency) VALUES(999999999, '', 0.0, 0, 0.0);

.mode tabs
.import $CORPUS/$CORPUS.tsv sentences
.import $CORPUS/$CORPUS.patterns.tsv patterns
.import $CORPUS/$CORPUS.reverse-index.tsv reverseindex

# remove sentences with uncommon patterns that fell below threshold
DELETE FROM sentences WHERE sentenceid IN (SELECT sentenceid FROM reverseindex WHERE pattern = '');
DELETE FROM patterns WHERE pattern = '';

# .mode column
# .headers on
# .fullschema
# SELECT * from sentences limit 10;
# SELECT * from reverseindex limit 10;
# SELECT * from patterns limit 10;
;


EOF

sqlite3 $CORPUS/$CORPUS.sqlite "select count(*) from sentences;"
