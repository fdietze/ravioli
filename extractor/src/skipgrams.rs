use itertools::Itertools;
use std::iter;
use unicode_segmentation::UnicodeSegmentation;

struct SkipGramChunks<'a> {
    src: &'a str,
    char_indices: Vec<usize>,
    bounds: Vec<usize>,
}

impl<'a> SkipGramChunks<'a> {
    fn new(src: &'a str, gaps: usize) -> SkipGramChunks {
        let char_indices: Vec<usize> = src
            // .grapheme_indices(true)
            .char_indices()
            .map(|(i, _)| i)
            .chain(iter::once(src.len()))
            .collect();
        let char_len = char_indices.len();
        SkipGramChunks {
            src: src,
            char_indices: char_indices,
            bounds: (0..((gaps + 1) * 2 - 1))
                .chain(iter::once(char_len - 1))
                .collect(),
        }
    }
}

impl<'a> Iterator for SkipGramChunks<'a> {
    type Item = (Vec<&'a str>, Vec<usize>);
    fn next(&mut self) -> Option<(Vec<&'a str>, Vec<usize>)> {
        // println!(
        //     "bounds:  {:?} {}",
        //     self.bounds.iter().tuples().collect::<Vec<(&usize, &usize)>>(),
        //     self.src
        // );
        let mut i = self.bounds.len() - 2; // don't touch the last pos
        if self.bounds[i] < self.bounds[i + 1] {
            let res = self
                .bounds
                .iter()
                .map(|&i| self.char_indices[i])
                .tuples()
                .map(|(a, b)| &self.src[a..b])
                .collect();
            let sizes = self
                .bounds
                .iter()
                .map(|&i| self.char_indices[i])
                .tuples()
                .map(|(a, b)| b - a)
                .collect();
            // println!("     {:?}", res);

            // println!("     i: {}", i);
            // self.bounds[i] += 1;
            // println!(
            //     "     {:?} {}",
            //     self.bounds.iter().tuples().collect::<Vec<(&usize, &usize)>>(),
            //     self.src
            // );
            while self.bounds[i] >= self.bounds[i + 1] - 1 && i > 1 {
                i -= 1;
                // println!("     i: {}", i);
            }
            self.bounds[i] += 1;
            while i < self.bounds.len() - 2 {
                self.bounds[i + 1] = self.bounds[i] + 1;
                // println!("     i: {}", i);
                // println!(
                //     "     {:?} {}",
                //     self.bounds.iter().tuples().collect::<Vec<(&usize, &usize)>>(),
                //     self.src
                // );
                i += 1;
            }

            // println!("\n");

            Some((res, sizes))
        } else {
            None
        }
    }
}

pub fn skipgrams_n<'a>(
    src: &'a str,
    gaps: usize,
) -> impl Iterator<Item = (Vec<&'a str>, Vec<usize>)> {
    SkipGramChunks::new(src, gaps)
}

pub fn skipgrams_all<'a>(src: &'a str) -> impl Iterator<Item = (Vec<&'a str>, Vec<usize>)> {
    let char_count = src.graphemes(true).count();
    let max_gaps = (char_count - 1) / 2;
    (1..=max_gaps).flat_map(move |gaps| skipgrams_n(src, gaps))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_gap() {
        let s = "abcdefg";
        let result: Vec<Vec<&str>> = skipgrams_n(s, 1).take(100).collect();
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
    fn two_gaps() {
        let s = "abcdefg";
        let result: Vec<Vec<&str>> = skipgrams_n(s, 2).take(100).collect();
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
    fn two_gaps_umlauts() {
        let s = "abödeäg";
        let result: Vec<Vec<&str>> = skipgrams_n(s, 2).take(100).collect();
        let expected: Vec<Vec<&str>> = vec![
            vec!["a", "ö", "eäg"],
            vec!["a", "ö", "äg"],
            vec!["a", "ö", "g"],
            vec!["a", "öd", "äg"],
            vec!["a", "öd", "g"],
            vec!["a", "öde", "g"],
            vec!["a", "d", "äg"],
            vec!["a", "d", "g"],
            vec!["a", "de", "g"],
            vec!["a", "e", "g"],
            vec!["ab", "d", "äg"],
            vec!["ab", "d", "g"],
            vec!["ab", "de", "g"],
            vec!["ab", "e", "g"],
            vec!["abö", "e", "g"],
        ];
        assert_eq!(result, expected);
    }

    #[test]
    fn all_skipgrams_umlauts() {
        let s = "abödeäg";
        let result: Vec<Vec<&str>> = skipgrams_all(s).take(100).collect();
        let expected: Vec<Vec<&str>> = vec![
            // 1 gap:
            vec!["a", "ödeäg"],
            vec!["a", "deäg"],
            vec!["a", "eäg"],
            vec!["a", "äg"],
            vec!["a", "g"],
            vec!["ab", "deäg"],
            vec!["ab", "eäg"],
            vec!["ab", "äg"],
            vec!["ab", "g"],
            vec!["abö", "eäg"],
            vec!["abö", "äg"],
            vec!["abö", "g"],
            vec!["aböd", "äg"],
            vec!["aböd", "g"],
            vec!["aböde", "g"],
            // 2 gaps:
            vec!["a", "ö", "eäg"],
            vec!["a", "ö", "äg"],
            vec!["a", "ö", "g"],
            vec!["a", "öd", "äg"],
            vec!["a", "öd", "g"],
            vec!["a", "öde", "g"],
            vec!["a", "d", "äg"],
            vec!["a", "d", "g"],
            vec!["a", "de", "g"],
            vec!["a", "e", "g"],
            vec!["ab", "d", "äg"],
            vec!["ab", "d", "g"],
            vec!["ab", "de", "g"],
            vec!["ab", "e", "g"],
            vec!["abö", "e", "g"],
            // 3 gaps:
            vec!["a", "ö", "e", "g"],
        ];
        assert_eq!(result, expected);
    }
}
