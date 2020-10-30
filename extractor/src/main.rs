use std::cmp;
mod flexgrams;
use flexgrams::flexgram_pattern;
mod corpus;
use corpus::Corpus;
use std::collections::HashMap;
use std::time::Instant;

fn main() {
    let c = Corpus::from_file("../subtitles_de_100k.txt");
    let threshold = 100;
    let max_flexgram_chunks = 2;

    let longest_line_character_count: usize = c.with_lines(|lines| {
        lines
            .iter()
            .map(|(_, char_indices)| char_indices.len())
            .max()
            .unwrap()
    });
    let mut ngram_max_size = 0;

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
            } else {
                ngram_max_size = size;
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

    println!("extracting flexgrams...");

    let mut flexgrams: HashMap<Vec<&str>, usize> = HashMap::new();
    c.with_lines(|lines| {
        let flexgram_start = Instant::now();
        for size in 3..=longest_line_character_count {
            println!("size {}/{}...", size, longest_line_character_count);
            let max_chunks = cmp::min((size - 1) / 2 + 1, max_flexgram_chunks);
            for chunks in 2..=max_chunks {
                let flexgram_start = Instant::now();
                let prev_count = flexgrams.len();
                let flexgram_pat = flexgram_pattern(size, chunks, ngram_max_size);
                // println!("flexgram_pattern({}, {}, {})", size, chunks, ngram_max_size);
                println!("  chunks {} (patterns: {})...", chunks, flexgram_pat.len());
                // for pat in flexgram_pat.iter() {
                //     println!("pattern: {:?}", pat);
                // }
                for (line, line_char_indices) in
                    lines.iter().filter(|(_, indices)| indices.len() >= size)
                {
                    for ngram in line_char_indices.windows(size + 1) {
                        flexgram_pat.iter().for_each(|pattern| {
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
                prune_counted(&mut flexgrams, threshold);
                println!("    kept: {}", flexgrams.len() - prev_count);
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
