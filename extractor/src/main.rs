use std::cmp;
mod flexgrams;
use flexgrams::flexgram_pattern;
mod corpus;
use corpus::Corpus;
use itertools::Itertools;
use std::collections::HashMap;
use std::time::Instant;
use unicode_segmentation::UnicodeSegmentation;

fn main() {
    let corpus = Corpus::from_file("../subtitles_de_100k.txt");
    let threshold = 100;
    let max_flexgram_chunks = 2;
    let max_ngram_coverage = 0.01;
    let max_corpus_coverage = 5.0;

    println!("extracting ngrams...");
    let mut ngrams: HashMap<&str, Vec<usize>> = HashMap::new();
    let ngram_start = Instant::now();
    corpus.with_lines(|lines| {
        let mut size = 1;
        println!("size {}...", size);

        let ngram_start = Instant::now();
        for (line_idx, (line, line_char_indices)) in lines.iter().enumerate() {
            // println!("{}: {}", line_idx, line);
            for ngram in line_char_indices.windows(size + 1) {
                let slice = &line[ngram[0]..ngram[ngram.len() - 1]];
                // println!("  {} ({:?})", slice, ngrams.get(slice).map(|x| x.len()));
                (*ngrams.entry(slice).or_insert(vec![])).push(line_idx);
            }
        }

        println!("  total: {}", ngrams.len());
        prune(&mut ngrams, threshold);
        println!("  kept: {}", ngrams.len());
        println!("  took: {:?}", ngram_start.elapsed());

        loop {
            let ngram_start = Instant::now();
            let prev_count = ngrams.len();
            size += 1;
            println!("size {}...", size);
            for (line_idx, (line, line_char_indices)) in lines.iter().enumerate() {
                // println!("{}: {}", line_idx, line);
                for ngram in line_char_indices.windows(size + 1) {
                    // let slice = &line[ngram[0]..ngram[ngram.len() - 1]];
                    // println!("  {} ({:?})", slice, ngrams.get(slice).map(|x| x.len()));
                    if ngram.windows(size).all(|ngram| {
                        let slice = &line[ngram[0]..ngram[ngram.len() - 1]];
                        ngrams.contains_key(slice)
                    }) {
                        let slice = &line[ngram[0]..ngram[ngram.len() - 1]];
                        (*ngrams.entry(slice).or_insert(vec![])).push(line_idx);
                    }
                }
            }
            println!("  total: {}", ngrams.len() - prev_count);
            prune(&mut ngrams, threshold);
            let kept = ngrams.len() - prev_count;
            println!("  kept: {}", kept);
            println!("  took: {:?}", ngram_start.elapsed());
            if kept == 0 {
                break;
            }
        }
    });
    println!("calculating coverage...");
    let mut ngram_coverage: HashMap<&str, f64> = ngrams
        .iter()
        .map(|(&s, lines)| {
            (
                s,
                corpus.with_total_characters(|&total_characters| {
                    (s.len() * lines.len()) as f64 / (total_characters as f64)
                }),
            )
        })
        .collect();

    ngrams.retain(|s, _| ngram_coverage[s] <= max_ngram_coverage);
    ngram_coverage.retain(|s, _| ngrams.contains_key(s));

    let ngram_top_cov: Vec<_> = ngram_coverage
        .iter()
        .sorted_by(|(_, cova), (_, covb)| covb.partial_cmp(cova).unwrap())
        .collect();
    {
        let last_ngram = ngram_top_cov
            .iter()
            .scan(0.0, |state, &(_, cov)| {
                *state = *state + cov;
                Some(*state)
            })
            .enumerate()
            .find(|(_, cov_sum)| *cov_sum >= max_corpus_coverage)
            .map(|(i, _)| i);
        println!("last ngram: {:?}", last_ngram);
        if let Some(i) = last_ngram {
            let removed_ngrams: Vec<&str> = ngram_top_cov
                .iter()
                .skip(i)
                .map(|(&ngram, _)| ngram)
                .collect();

            for ngram in removed_ngrams.iter() {
                ngrams.remove(*ngram);
                ngram_coverage.remove(*ngram);
            }
        };
    }
    // TODO: sorting again and shadowing should not be necessary, but there are borrowing problems...
    let ngram_top_cov: Vec<_> = ngram_coverage
        .iter()
        .sorted_by(|(_, cova), (_, covb)| covb.partial_cmp(cova).unwrap())
        .collect();

    for (pattern, sentences) in ngram_top_cov.iter().take(100) {
        println!("{}: {}", pattern, sentences);
    }

    println!("all ngrams took: {:?}", ngram_start.elapsed());

    println!("extracting flexgrams...");

    let ngram_max_size = ngrams
        .iter()
        .map(|(&ngram, _)| ngram.graphemes(true).count())
        .max()
        .unwrap();
    println!("longest ngram: {}", ngram_max_size);
    let mut flexgrams: HashMap<Vec<&str>, usize> = HashMap::new();
    let longest_line_character_count: usize = corpus.with_lines(|lines| {
        lines
            .iter()
            .map(|(_, char_indices)| char_indices.len())
            .max()
            .unwrap()
    });
    corpus.with_lines(|lines| {
        let flexgram_start = Instant::now();
        for size in 3..=longest_line_character_count {
            println!("size {}/{}...", size, longest_line_character_count);
            let max_chunks = cmp::min((size - 1) / 2 + 1, max_flexgram_chunks);
            for chunks in 2..=max_chunks {
                let flexgram_start = Instant::now();
                let prev_count = flexgrams.len();
                let flexgram_pat = flexgram_pattern(size, chunks, ngram_max_size);
                println!("  chunks {} (patterns: {})...", chunks, flexgram_pat.len());
                // for pat in flexgram_pat.iter() {
                //     println!("  pattern: {:?}", pat);
                // }
                for (line, line_char_indices) in
                    lines.iter().filter(|(_, indices)| indices.len() > size)
                {
                    // println!("  {}", line);
                    for ngram in line_char_indices.windows(size + 1) {
                        // let slice = &line[ngram[0]..ngram[ngram.len() - 1]];
                        // println!("    {}", slice);
                        flexgram_pat.iter().for_each(|pattern| {
                            // let flexgram: Vec<_> = pattern
                            //     .iter()
                            //     .map(|(from, to)| &line[ngram[*from]..ngram[*to]])
                            //     .collect();
                            // println!("      {:?} ({:?})", flexgram, flexgrams.get(&flexgram));
                            // validate without allocating first
                            let flexgram_valid = pattern.iter().all(|(from, to)| {
                                ngrams.contains_key(&line[ngram[*from]..ngram[*to]])
                            });

                            //TODO: if one chunk is not in the hashmap don't even
                            //enumerate the other patterns containing this chunk

                            if flexgram_valid {
                                let flexgram = pattern
                                    .iter()
                                    .map(|(from, to)| &line[ngram[*from]..ngram[*to]])
                                    .collect();
                                (*flexgrams.entry(flexgram).or_insert(0)) += 1;
                            }
                        })
                    }
                }
                println!("    total: {}", flexgrams.len() - prev_count);
                println!("    took: {:?}", flexgram_start.elapsed());
            }
        }
        println!("all flexgrams took: {:?}", flexgram_start.elapsed());

        println!("printing top flexgrams...");
        let top = {
            let mut counts: Vec<(&Vec<&str>, &usize)> = flexgrams.iter().collect();
            counts.sort_by(|a, b| b.1.cmp(&a.1));
            counts
        };

        println!("{}", top.len());

        for (index, (skipgram, count)) in top.iter().enumerate().take(10000) {
            println!("{} {:?}: {}", index, skipgram, count);
        }
    });
}

fn prune<T: Eq + std::hash::Hash>(line_references: &mut HashMap<T, Vec<usize>>, threshold: usize) {
    line_references.retain(|_, lines| lines.len() >= threshold);
}

fn prune_counted<T: Eq + std::hash::Hash>(
    line_references: &mut HashMap<T, usize>,
    threshold: usize,
) {
    line_references.retain(|_, lines| *lines >= threshold);
}
