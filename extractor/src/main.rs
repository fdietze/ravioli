mod ngrams;
use std::cmp;
use std::iter;
mod flexgrams;
use flexgrams::flexgram_pattern;
use ngrams::ngrams_iter;
mod corpus;
use corpus::Corpus;
use std::collections::HashMap;
use std::time::Instant;

fn main() {
    let c = Corpus::from_file("../subtitles_de_100k.txt");
    let threshold = 30;
    let max_flexgram_chunks = 2;

    println!("extracting ngrams...");
    let mut ngrams: HashMap<&str, Vec<usize>> = HashMap::new();
    let ngram_start = Instant::now();
    c.with_lines(|lines| {
        let mut size = 1;
        println!("size {}...", size);

        let ngram_start = Instant::now();
        for (line_idx, line) in lines.iter().enumerate() {
            for ngram in ngrams_iter(&line, size) {
                // println!("{}", ngram);
                (*ngrams.entry(ngram).or_insert(vec![])).push(line_idx);
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
            for (line_idx, line) in lines.iter().enumerate() {
                for ngram in ngrams_iter(&line, size) {
                    if ngrams_iter(&ngram, size - 1).all(|ngram| ngrams.contains_key(ngram)) {
                        (*ngrams.entry(ngram).or_insert(vec![])).push(line_idx);
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

    let flexgram_start = Instant::now();
    let mut flexgrams: HashMap<Vec<&str>, Vec<usize>> = HashMap::new();
    c.with_lines(|lines| {
        for size in 3..=ngram_max_size {
            println!("size {}...", size);
            let max_chunks = cmp::min((size - 1) / 2 + 1, max_flexgram_chunks);
            for chunks in 2..=max_chunks {
                println!("  chunks {}...", chunks);
                let flexgram_start = Instant::now();
                let flexgram_pat = flexgram_pattern(size, chunks, ngram_max_size);
                // println!("patterns: {:?}", flexgram_pat);
                for (line_idx, line) in lines.iter().enumerate() {
                    for ngram in ngrams_iter(&line, size) {
                        //TODO: calculate only once per line, or even never, using bytes and
                        //utf-8
                        let indices: Vec<usize> = ngram
                            .char_indices()
                            .map(|(i, _)| i)
                            .chain(iter::once(ngram.len()))
                            .collect();
                        flexgram_pat.iter().for_each(|pattern| {
                            let flexgram = pattern
                                .iter()
                                .map(|(from, to)| &ngram[indices[*from]..indices[*to]])
                                .collect();
                            (*flexgrams.entry(flexgram).or_insert(vec![])).push(line_idx);
                        })

                        // for flexgram in flexgrams_iter(ngram, &flexgram_pat) {
                        //     if flexgram.iter().all(|ngram| ngrams.contains_key(ngram)) {
                        //         (*flexgrams.entry(flexgram).or_insert(vec![])).push(&line);
                        //     }
                        // }
                    }
                }
                println!("    total: {}", flexgrams.len());
                prune(&mut flexgrams, threshold);
                println!("    kept: {}", flexgrams.len());
                println!("    took: {:?}", flexgram_start.elapsed());
                if flexgrams.len() == 0 {
                    break;
                }
            }
        }

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

        for (skipgram, count) in top.iter().take(10000) {
            println!("{:?}: {}", skipgram, count);
        }
    });
    println!("all flexgrams: {:?}", flexgram_start.elapsed());
}

fn prune<T: Eq + std::hash::Hash>(line_references: &mut HashMap<T, Vec<usize>>, threshold: usize) {
    line_references.retain(|_, lines| lines.len() >= threshold);
}
