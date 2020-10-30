use itertools::Itertools;
use std::iter;

struct SkipGramChunks {
    bounds: Vec<usize>,
}

impl SkipGramChunks {
    fn new(length: usize, chunks: usize) -> SkipGramChunks {
        SkipGramChunks {
            bounds: (0..((chunks - 1) * 2) + 1)
                .chain(iter::once(length))
                .collect(),
        }
    }
}

impl Iterator for SkipGramChunks {
    type Item = Vec<(usize, usize)>;
    fn next(&mut self) -> Option<Vec<(usize, usize)>> {
        // println!(
        //     "bo:  {:?}",
        //     self.bounds
        //         .iter()
        //         .tuples()
        //         .collect::<Vec<(&usize, &usize)>>(),
        // );
        let mut i = self.bounds.len() - 2; // don't touch the last pos
        if self.bounds[i] < self.bounds[i + 1] {
            let res = self.bounds.iter().map(|&i| i).tuples().collect();
            // println!("     {:?}", res);

            // println!("     i: {}", i);
            // println!(
            //     "     {:?} {}",
            //     self.bounds.iter().tuples().collect::<Vec<(&usize, &usize)>>(),
            // );
            while i > 1 && self.bounds[i + 1] - self.bounds[i] <= 1 {
                i -= 1;
                // println!("     i: {}", i);
            }
            self.bounds[i] += 1;
            while i < self.bounds.len() - 2 {
                self.bounds[i + 1] = self.bounds[i] + 1;
                // println!("     i: {}", i);
                // println!(
                //     "     {:?}",
                //     self.bounds
                //         .iter()
                //         .tuples()
                //         .collect::<Vec<(&usize, &usize)>>()
                // );
                i += 1;
            }

            // println!("\n");

            Some(res)
        } else {
            None
        }
    }
}

pub fn flexgram_pattern(
    length: usize,
    chunks: usize,
    max_chunk_size: usize,
) -> Vec<Vec<(usize, usize)>> {
    SkipGramChunks::new(length, chunks)
        .filter(move |tuples| tuples.iter().all(|(from, to)| to - from <= max_chunk_size))
        .collect()
}

pub fn flexgrams_iter<'a>(
    src: &'a str,
    patterns: &'a Vec<Vec<(usize, usize)>>,
) -> impl Iterator<Item = Vec<&'a str>> {
    let indices: Vec<usize> = src
        .char_indices()
        .map(|(i, _)| i)
        .chain(iter::once(src.len()))
        .collect();
    patterns.iter().map(move |pattern| {
        pattern
            .iter()
            .map(|(from, to)| &src[indices[*from]..indices[*to]])
            .collect()
    })
}

// pub fn flexgrams_str<'a>(src: &'a str, chunks: usize, max_chunk_size: usize) -> Vec<Vec<&'a str>> {
//     let length = src.chars().count();
//     let patterns = flexgram_pattern(length, chunks, max_chunk_size);
//     flexgrams_iter(src, &patterns).collect()
// }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_gap() {
        let s = "abcdefg";
        let length = s.chars().count();
        let pattern = flexgram_pattern(length, 2, 100);
        let result: Vec<Vec<&str>> = flexgrams_iter(s, &pattern).collect();
        let expected: Vec<Vec<&str>> = vec![
            vec!["a", "cdefg"],
            vec!["a", "defg"],
            vec!["a", "efg"],
            vec!["a", "fg"],
            vec!["a", "g"],
            vec!["ab", "defg"],
            vec!["ab", "efg"],
            vec!["ab", "fg"],
            vec!["ab", "g"],
            vec!["abc", "efg"],
            vec!["abc", "fg"],
            vec!["abc", "g"],
            vec!["abcd", "fg"],
            vec!["abcd", "g"],
            vec!["abcde", "g"],
        ];
        assert_eq!(result, expected);
    }

    #[test]
    fn one_gap_max_chunk() {
        let s = "abcdefg";
        let length = s.chars().count();
        let pattern = flexgram_pattern(length, 2, 3);
        let result: Vec<Vec<&str>> = flexgrams_iter(s, &pattern).collect();
        let expected: Vec<Vec<&str>> = vec![
            vec!["a", "efg"],
            vec!["a", "fg"],
            vec!["a", "g"],
            vec!["ab", "efg"],
            vec!["ab", "fg"],
            vec!["ab", "g"],
            vec!["abc", "efg"],
            vec!["abc", "fg"],
            vec!["abc", "g"],
        ];
        assert_eq!(result, expected);
    }

    #[test]
    fn two_gaps() {
        let s = "abcdefg";
        let length = s.chars().count();
        let pattern = flexgram_pattern(length, 3, 100);
        let result: Vec<Vec<&str>> = flexgrams_iter(s, &pattern).collect();
        let expected: Vec<Vec<&str>> = vec![
            vec!["a", "c", "efg"],
            vec!["a", "c", "fg"],
            vec!["a", "c", "g"],
            vec!["a", "cd", "fg"],
            vec!["a", "cd", "g"],
            vec!["a", "cde", "g"],
            vec!["a", "d", "fg"],
            vec!["a", "d", "g"],
            vec!["a", "de", "g"],
            vec!["a", "e", "g"],
            vec!["ab", "d", "fg"],
            vec!["ab", "d", "g"],
            vec!["ab", "de", "g"],
            vec!["ab", "e", "g"],
            vec!["abc", "e", "g"],
        ];
        assert_eq!(result, expected);
    }

    #[test]
    fn two_gaps_max_chunk() {
        let s = "abcdefg";
        let length = s.chars().count();
        let pattern = flexgram_pattern(length, 3, 2);
        let result: Vec<Vec<&str>> = flexgrams_iter(s, &pattern).collect();
        let expected: Vec<Vec<&str>> = vec![
            vec!["a", "c", "fg"],
            vec!["a", "c", "g"],
            vec!["a", "cd", "fg"],
            vec!["a", "cd", "g"],
            vec!["a", "d", "fg"],
            vec!["a", "d", "g"],
            vec!["a", "de", "g"],
            vec!["a", "e", "g"],
            vec!["ab", "d", "fg"],
            vec!["ab", "d", "g"],
            vec!["ab", "de", "g"],
            vec!["ab", "e", "g"],
        ];
        assert_eq!(result, expected);
    }

    #[test]
    fn two_gaps_max_chunk_small() {
        let s = "abcdefg";
        let length = s.chars().count();
        let pattern = flexgram_pattern(length, 3, 1);
        let result: Vec<Vec<&str>> = flexgrams_iter(s, &pattern).collect();
        let expected: Vec<Vec<&str>> = vec![
            vec!["a", "c", "g"],
            vec!["a", "d", "g"],
            vec!["a", "e", "g"],
        ];
        assert_eq!(result, expected);
    }

    #[test]
    fn two_gaps_max_chunk_two() {
        let s = "abcdefghi";
        let length = s.chars().count();
        let pattern = flexgram_pattern(length, 3, 2);
        let result: Vec<Vec<&str>> = flexgrams_iter(s, &pattern).collect();
        let expected: Vec<Vec<&str>> = vec![
            vec!["a", "c", "hi"],
            vec!["a", "c", "i"],
            vec!["a", "cd", "hi"],
            vec!["a", "cd", "i"],
            vec!["a", "d", "hi"],
            vec!["a", "d", "i"],
            vec!["a", "de", "hi"],
            vec!["a", "de", "i"],
            vec!["a", "e", "hi"],
            vec!["a", "e", "i"],
            vec!["a", "ef", "hi"],
            vec!["a", "ef", "i"],
            vec!["a", "f", "hi"],
            vec!["a", "f", "i"],
            vec!["a", "fg", "i"],
            vec!["a", "g", "i"],
            vec!["ab", "d", "hi"],
            vec!["ab", "d", "i"],
            vec!["ab", "de", "hi"],
            vec!["ab", "de", "i"],
            vec!["ab", "e", "hi"],
            vec!["ab", "e", "i"],
            vec!["ab", "ef", "hi"],
            vec!["ab", "ef", "i"],
            vec!["ab", "f", "hi"],
            vec!["ab", "f", "i"],
            vec!["ab", "fg", "i"],
            vec!["ab", "g", "i"],
        ];
        assert_eq!(result, expected);
    }
}
