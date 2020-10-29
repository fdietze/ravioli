mod char_windows;
use std::cmp;
mod skipgrams;
use char_windows::grapheme_windows;
use skipgrams::skipgrams_n;
mod corpus;
use corpus::Corpus;
use rayon::prelude::*;
use std::collections::HashMap;

fn main() {
    let c = Corpus::from_file("../subtitles_de_10k.txt");
    let threshold = 30;
    let max_skipgram_gaps = 1;

    println!("extracting ngrams...");
    let mut ngrams: Vec<HashMap<&str, Vec<&str>>> = Vec::new();
    c.with_lines(|lines| {
        let mut size = 1;
        println!("size {}...", size);

        let mut patterns: HashMap<&str, Vec<&str>> = HashMap::new();
        for line in lines.iter() {
            for ngram in grapheme_windows(&line, size) {
                // println!("{}", ngram);
                (*patterns.entry(ngram).or_insert(vec![])).push(&line);
            }
        }
        println!("  total: {}", patterns.len());
        prune(&mut patterns, threshold);
        println!("  kept: {}", patterns.len());
        ngrams.push(patterns);

        loop {
            let prev_patterns = &ngrams[size - 1];
            // println!("{:?}", prev_patterns.keys());
            size += 1;
            let mut patterns: HashMap<&str, Vec<&str>> = HashMap::new();
            println!("size {}...", size);
            for line in lines.iter() {
                for ngram in grapheme_windows(&line, size) {
                    if grapheme_windows(&ngram, size - 1)
                        .all(|ngram| prev_patterns.contains_key(ngram))
                    {
                        (*patterns.entry(ngram).or_insert(vec![])).push(&line);
                    }
                }
            }
            println!("  total: {}", patterns.len());
            prune(&mut patterns, threshold);
            println!("  kept: {}", patterns.len());
            if patterns.len() == 0 {
                break;
            }
            ngrams.push(patterns);
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

    let ngram_max_size = ngrams.len();
    println!("extracting skipgrams...");
    let mut skipgrams: HashMap<Vec<&str>, Vec<&str>> = HashMap::new();
    c.with_lines(|lines| {
        for size in 3..=ngram_max_size {
            println!("size {}...", size);
            let max_gaps = cmp::min((size - 1) / 2, max_skipgram_gaps);
            for gaps in 1..=max_gaps {
                println!("  gaps {}...", gaps);
                for line in lines.iter() {
                    for ngram in grapheme_windows(&line, size) {
                        for (skipgram, sizes) in skipgrams_n(ngram, gaps) {
                            if skipgram
                                .iter()
                                .zip(sizes.iter())
                                .all(|(ngram, charcount)| ngrams[charcount - 1].contains_key(ngram))
                            {
                                (*skipgrams.entry(skipgram).or_insert(vec![])).push(&line);
                            }
                        }
                    }
                }
                println!("    total: {}", skipgrams.len());
                prune(&mut skipgrams, threshold);
                println!("    kept: {}", skipgrams.len());
                if skipgrams.len() == 0 {
                    break;
                }
            }
        }

        println!("printing top skipgrams...");
        let top = {
            let mut counts: Vec<(&Vec<&str>, usize)> = skipgrams
                .iter()
                .map(|(skipgram, sentences)| (skipgram, sentences.len()))
                .collect();
            counts.sort_by(|a, b| b.1.cmp(&a.1));
            counts
        };

        println!("{}", top.len());

        for (skipgram, count) in top.iter().take(10000) {
            println!("{:?}: {}", skipgram, count);
        }
    });
}

fn prune<T: Eq + std::hash::Hash>(line_references: &mut HashMap<T, Vec<&str>>, threshold: usize) {
    line_references.retain(|_, lines| lines.len() >= threshold);
}
