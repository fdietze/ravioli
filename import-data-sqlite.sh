#!/usr/bin/env bash
set -e # exit when one command fails


# TODO frequency is imported as INF


CORPUS=$1

MIN_SENTENCE_OCCURRENCES=5

rm -f $CORPUS/$CORPUS.sqlite
cat << EOF | sqlite3 $CORPUS/$CORPUS.sqlite

.bail on
PRAGMA foreign_keys = ON;


SELECT "importing all sentences...";
CREATE TABLE rawsentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  sentence TEXT NOT NULL
);
CREATE INDEX rawsentences_sentence_idx ON rawsentences (sentence); -- will be replaced by unique index later
.mode tabs
.import $CORPUS/$CORPUS.tsv rawsentences




SELECT "Store duplicate sentences only once with their occurrence count...";
CREATE TABLE sentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  sentence TEXT NOT NULL UNIQUE,
  occurrences INTEGER NOT NULL,
  coverage REAL NOT NULL
);
CREATE INDEX sentences_occurrences_idx ON sentences (occurrences);
CREATE INDEX sentences_coverage_idx ON sentences (coverage);
INSERT INTO sentences (sentenceid, sentence, occurrences, coverage)
    SELECT min(sentenceid) as sentenceid, sentence, count(sentenceid) as occurrences, CAST(count(sentenceid) as REAL) / (SELECT COUNT(*) FROM rawsentences) as coverage FROM rawsentences group by sentence;
DROP TABLE rawsentences;

SELECT "remove uncommon sentences (occurrence < $MIN_SENTENCE_OCCURRENCES)...";
delete FROM sentences WHERE occurrences < $MIN_SENTENCE_OCCURRENCES;


SELECT "importing patterns...";
CREATE TABLE patterns(
  rank INTEGER NOT NULL UNIQUE,
  pattern TEXT NOT NULL PRIMARY KEY,
  coverage REAL NOT NULL,
  size INTEGER NOT NULL,
  frequency REAL NOT NULL
);
.mode tabs
.import $CORPUS/$CORPUS.patterns.tsv patterns
-- insert empty pattern to fulfill reverseindex foreign key constraint
INSERT INTO "patterns"(rank,pattern,coverage,size,frequency) VALUES(999999999, '', 0.0, 0, 0.0);


SELECT "importing reverseindex...";
CREATE TABLE reverseindex(
    sentenceid INTEGER NOT NULL,
    position INTEGER NOT NULL,
    pattern TEXT NOT NULL,

    PRIMARY KEY (sentenceid, position, pattern)
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
EOF



# separate session to ignore foreign key errors
cat << EOF | sqlite3 $CORPUS/$CORPUS.sqlite 2> /dev/null || true
PRAGMA foreign_keys = ON;
.mode tabs
.import $CORPUS/$CORPUS.reverse-index.tsv reverseindex
EOF



cat << EOF | sqlite3 $CORPUS/$CORPUS.sqlite
.bail on
PRAGMA foreign_keys = ON;


SELECT "remove sentences with unknown patterns (below counted threshold)...";
DELETE FROM sentences WHERE sentenceid IN (SELECT sentenceid FROM reverseindex WHERE pattern = '');
DELETE FROM patterns WHERE pattern = '';
-- SELECT sentence, occurrences, (MAX(position)+1)-COUNT(DISTINCT position) as missing, length(sentence)-length(replace(sentence, ' ', ''))+1-COUNT(DISTINCT position) as missing2, GROUP_CONCAT(DISTINCT position) FROM sentences s JOIN reverseindex r ON r.sentenceid = s.sentenceid GROUP BY s.sentenceid HAVING missing2 > 0 order by occurrences limit 100;
DELETE FROM sentences WHERE sentenceid IN (SELECT s.sentenceid FROM sentences s JOIN reverseindex r ON r.sentenceid = s.sentenceid GROUP BY s.sentenceid HAVING length(sentence)-length(replace(sentence, ' ', ''))+1-COUNT(DISTINCT position) > 0);


SELECT "remove patterns that don't appear in any sentence...";
-- SELECT p.rank,p.pattern,count(r.sentenceid) sentence_count FROM patterns p left outer JOIN reverseindex r on r.pattern = p.pattern group by p.rank HAVING sentence_count = 0 order by p.rank;
delete FROM patterns WHERE rank IN (SELECT p.rank FROM patterns p left outer JOIN reverseindex r on r.pattern = p.pattern group by p.rank HAVING count(r.sentenceid) = 0);






.mode column
.headers on
SELECT count(*) as sentences_count FROM sentences;
SELECT count(*) as patterns_count FROM patterns;
SELECT count(*) as reverseindex_count FROM reverseindex;




-- prepare learning tests
CREATE TABLE tick(
    time INTEGER NOT NULL
);

INSERT INTO tick(time) VALUES (0);
ALTER TABLE patterns ADD COLUMN next_test INTEGER NOT NULL DEFAULT 0;
ALTER TABLE patterns ADD COLUMN proficiency INTEGER NOT NULL DEFAULT 2;




.fullschema

.headers off
SELECT "vacuum...";
VACUUM;

SELECT "checking database integrity...";
PRAGMA integrity_check;
;


EOF


ls -lh $CORPUS/$CORPUS.sqlite
