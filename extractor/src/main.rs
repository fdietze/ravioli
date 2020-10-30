use std::cmp;
mod flexgrams;
use flexgrams::flexgram_pattern;
mod corpus;
use corpus::Corpus;
use std::collections::HashMap;
use std::time::Instant;

fn main() {
    let c = Corpus::from_file("../subtitles_de_100k.txt");
    let threshold = 500;
    let max_flexgram_chunks = 2;

    println!("extracting ngrams...");
    let mut ngrams: HashMap<&str, Vec<usize>> = HashMap::new();
    let ngram_start = Instant::now();
    c.with_lines(|lines| {
        let mut size = 1;
        println!("size {}...", size);

        let ngram_start = Instant::now();
        for (line_idx, (line, line_char_indices)) in lines.iter().enumerate() {
            for ngram in line_char_indices.windows(size + 1) {
                let slice = &line[ngram[0]..ngram[ngram.len() - 1]];
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
                for ngram in line_char_indices.windows(size + 1) {
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

        // let top = {
        //     let mut counts: Vec<_> = patterns.iter().collect();
        //     counts.sort_by(|&a, b| b.1.cmp(a.1));
        //     counts
        // };

        // for (pattern, sentences) in top.iter().take(20) {
        //     println!("{}: {}", pattern, sentences.len());
        // }
    });
    println!("all ngrams: {:?}", ngram_start.elapsed());

    let ngram_max_size = ngrams.len();
    println!("extracting flexgrams...");

    let mut flexgrams: HashMap<Vec<&str>, Vec<usize>> = HashMap::new();
    c.with_lines(|lines| {
        let flexgram_start = Instant::now();
        for size in 3..=ngram_max_size {
            println!("size {}...", size);
            let max_chunks = cmp::min((size - 1) / 2 + 1, max_flexgram_chunks);
            for chunks in 2..=max_chunks {
                let flexgram_start = Instant::now();
                let prev_count = flexgrams.len();
                let flexgram_pat = flexgram_pattern(size, chunks, ngram_max_size);
                println!("  chunks {} (patterns: {})...", chunks, flexgram_pat.len());
                // println!("patterns: {:?}", flexgram_pat);
                for (line_idx, (line, line_char_indices)) in lines.iter().enumerate() {
                    for ngram in line_char_indices.windows(size + 1) {
                        flexgram_pat.iter().for_each(|pattern| {
                            let flexgram: Vec<&str> = pattern
                                .iter()
                                .map(|(from, to)| &line[ngram[*from]..ngram[*to]])
                                .collect();
                            if flexgram.iter().all(|ngram| ngrams.contains_key(ngram)) {
                                (*flexgrams.entry(flexgram).or_insert(vec![])).push(line_idx);
                            }
                        })
                    }
                }
                println!("    total: {}", flexgrams.len() - prev_count);
                prune(&mut flexgrams, threshold);
                println!("    kept: {}", flexgrams.len() - prev_count);
                println!("    took: {:?}", flexgram_start.elapsed());
            }
        }
        println!("all flexgrams took: {:?}", flexgram_start.elapsed());

        println!("printing top flexgrams...");
        let top = {
            let mut counts: Vec<(&Vec<&str>, usize)> = flexgrams
                .iter()
                .map(|(flexgram, sentences)| (flexgram, sentences.len()))
                .collect();
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
