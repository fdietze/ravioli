#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.


SQLITEDB=$1
SENTENCES=$2
PATTERNS=$3
REVERSEINDEX=$4
LANG3=$5

MIN_SENTENCE_OCCURRENCES=4
KEEP_SENTENCES_PER_PATTERN=10
TRANSLATIONFILE="out/translations_opensub/translations.sqlite"

PATTERNSCOREFN='2*(1/p.coverage) * 1/MAX(s.coverage)'

rm -f "$SQLITEDB"
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


SELECT "importing sentences...";
CREATE TABLE rawsentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  sentence TEXT NOT NULL,
  tokenized TEXT NOT NULL
);
.mode tabs
.import '$SENTENCES' rawsentences
CREATE INDEX rawsentences_sentence_idx ON rawsentences (sentence);




SELECT "storing duplicate sentences only once with their coverage...";
CREATE TABLE sentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  sentence TEXT NOT NULL UNIQUE,
  tokenized TEXT NOT NULL,
  coverage REAL NOT NULL
);
INSERT INTO sentences (sentenceid, sentence, tokenized, coverage)
SELECT MIN(sentenceid) AS sentenceid, sentence, tokenized, CAST(COUNT(sentenceid) AS REAL) / (SELECT COUNT(*) FROM rawsentences) AS coverage FROM rawsentences GROUP BY sentence;

CREATE INDEX sentences_coverage_idx ON sentences (coverage);

SELECT "removing uncommon sentences (occurrence < $MIN_SENTENCE_OCCURRENCES)...";
delete FROM sentences WHERE coverage < (CAST($MIN_SENTENCE_OCCURRENCES as real) / (SELECT COUNT(*) FROM rawsentences));
SELECT '  -' || changes(*);

DROP TABLE rawsentences;


SELECT "removing untranslatable sentences...";
attach '$TRANSLATIONFILE' as tr;
DELETE FROM sentences WHERE sentenceid IN
    (SELECT s.sentenceid
    FROM sentences s
    LEFT OUTER JOIN tr.sentences t on s.sentence = t.sentence and t.lang = '$LANG3'
    WHERE t.sentence IS NULL);
SELECT '  -' || changes(*);


SELECT "importing patterns...";
CREATE TABLE patterns(
  rank INTEGER NOT NULL, -- becomes rowid
  pattern TEXT NOT NULL PRIMARY KEY,
  coverage REAL NOT NULL
) WITHOUT ROWID;
.mode tabs
.import '$PATTERNS' patterns
-- insert empty pattern to fulfill reverseindex foreign key constraint
INSERT INTO "patterns"(rank,pattern,coverage) VALUES(999999999, '', 0.0);

EOF



# separate session to ignore foreign key errors
cat << EOF | sqlite3 -init "" "$SQLITEDB" 2> /dev/null || true
.output /dev/null
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size=10000;
PRAGMA mmap_size = 30000000000;
.output

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

.mode tabs
.import '$REVERSEINDEX' reverseindex

CREATE INDEX reverseindex_position_idx ON reverseindex (position);
CREATE INDEX reverseindex_pattern_idx ON reverseindex (pattern);
EOF



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


SELECT "removing sentences where not all tokens are referenced in patterns (below counted threshold)...";
DELETE FROM sentences WHERE sentenceid IN (SELECT sentenceid FROM reverseindex WHERE pattern = '');
DELETE FROM patterns WHERE pattern = '';
-- SELECT sentence, (MAX(position)+1)-COUNT(DISTINCT position) as missing, length(tokenized)-length(replace(tokenized, ' ', ''))+1-COUNT(DISTINCT position) as missing2, GROUP_CONCAT(DISTINCT position) FROM sentences s JOIN reverseindex r ON r.sentenceid = s.sentenceid GROUP BY s.sentenceid HAVING missing2 > 0 order by coverage limit 100;
-- If there are more tokens than positions in the reverseindex, remove the sentence
DELETE FROM sentences
WHERE sentenceid IN (
    SELECT s.sentenceid
    FROM sentences s
    LEFT OUTER JOIN reverseindex r ON r.sentenceid = s.sentenceid
    GROUP BY s.sentenceid
    -- length(tokenized) - length(tokenized without spaces) + 1 = number of tokens
    HAVING length(tokenized) - length(replace(tokenized, ' ', '')) + 1 > COUNT(DISTINCT position));


SELECT "removing patterns that don't appear in any sentence...";
-- SELECT p.rank,p.pattern,count(r.sentenceid) sentence_count FROM patterns p left outer JOIN reverseindex r on r.pattern = p.pattern group by p.rank HAVING sentence_count = 0 order by p.rank;
DELETE FROM patterns WHERE rank IN (SELECT p.rank FROM patterns p left outer JOIN reverseindex r on r.pattern = p.pattern group by p.rank HAVING count(r.sentenceid) = 0);

-- SELECT "keep min $KEEP_SENTENCES_PER_PATTERN sentences per pattern, delete the rest...";
DELETE FROM sentences WHERE sentenceid NOT IN (
    SELECT sentenceid FROM (SELECT r.sentenceid, RANK() OVER (PARTITION BY r.pattern ORDER BY s.coverage DESC) rnk FROM reverseindex r JOIN sentences s ON s.sentenceid = r.sentenceid) 
    WHERE rnk <= $KEEP_SENTENCES_PER_PATTERN
);




CREATE INDEX patterns_rank_idx ON patterns(rank);

SELECT "removing 'tokenized' column from sentences...";
CREATE TEMPORARY TABLE sentences_backup(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  sentence TEXT NOT NULL,
  coverage REAL NOT NULL
) WITHOUT ROWID;
INSERT INTO sentences_backup SELECT sentenceid, sentence, coverage FROM sentences;
PRAGMA foreign_keys = OFF;
DROP TABLE sentences;
CREATE TABLE sentences(
  sentenceid INTEGER NOT NULL PRIMARY KEY,
  sentence TEXT NOT NULL,
  coverage REAL NOT NULL
) WITHOUT ROWID;
INSERT INTO sentences SELECT * FROM sentences_backup;
DROP TABLE sentences_backup;
PRAGMA foreign_keys = ON;


-- TODO:
-- SELECT "removing 'position' column from reverseindex...";
-- CREATE TEMPORARY TABLE reverseindex_backup(
--     sentenceid INTEGER NOT NULL,
--     pattern TEXT NOT NULL
-- );
-- INSERT INTO reverseindex_backup SELECT sentenceid, pattern FROM reverseindex;
-- DROP TABLE reverseindex;
-- CREATE TABLE reverseindex(
--     sentenceid INTEGER NOT NULL,
--     pattern TEXT NOT NULL,

--     PRIMARY KEY (sentenceid, pattern)
--     FOREIGN KEY (sentenceid)
--         REFERENCES sentences (sentenceid)
--         ON UPDATE CASCADE
--         ON DELETE CASCADE
--     FOREIGN KEY (pattern)
--         REFERENCES patterns (pattern)
--         ON UPDATE CASCADE
--         ON DELETE CASCADE
-- );
-- INSERT INTO reverseindex SELECT sentenceid, pattern FROM reverseindex_backup;
-- DROP TABLE reverseindex_backup;



SELECT "calculationg pattern scores...";
ALTER TABLE patterns ADD COLUMN score REAL NOT NULL DEFAULT 0;
UPDATE patterns SET score = (SELECT ${PATTERNSCOREFN} as score FROM patterns p JOIN reverseindex r ON r.pattern = p.pattern JOIN sentences s ON s.sentenceid = r.sentenceid WHERE p.rank = patterns.rank);
CREATE INDEX patterns_score_idx ON patterns (score);



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
ALTER TABLE patterns ADD COLUMN proficiency INTEGER NOT NULL DEFAULT 0;
CREATE INDEX patterns_next_test_idx ON patterns(next_test);




-- .fullschema

.headers off
SELECT "optimize...";
ANALYZE;
PRAGMA optimize;
SELECT "vacuum...";
VACUUM;
;



EOF


ls -lh "$SQLITEDB"
