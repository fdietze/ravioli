use unicode_segmentation::UnicodeSegmentation;

// pub fn grapheme_windows<'a>(src: &'a str, win_size: usize) -> impl Iterator<Item = &'a str> {
//     src.grapheme_indices(true).flat_map(move |(from, _)| {
//         src[from..]
//             .grapheme_indices(true)
//             .skip(win_size - 1)
//             .next()
//             .map(|(to, c)| &src[from..from + to + c.len()])
//     })
// }

pub fn grapheme_windows<'a>(src: &'a str, win_size: usize) -> impl Iterator<Item = &'a str> {
    src.char_indices().flat_map(move |(from, _)| {
        src[from..]
            .char_indices()
            .skip(win_size - 1)
            .next()
            .map(|(to, c)| &src[from..from + to + c.len_utf8()])
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty() {
        let s = "";
        let result: Vec<&str> = grapheme_windows(s, 5).collect();
        let expected: Vec<&str> = vec![];
        assert_eq!(result, expected);
    }

    #[test]
    fn two() {
        let s = "abcd";
        let result: Vec<&str> = grapheme_windows(s, 2).collect();
        let expected: Vec<&str> = vec!["ab", "bc", "cd"];
        assert_eq!(result, expected);
    }

    #[test]
    fn long() {
        let s = "abcdefghijkl";
        let result: Vec<&str> = grapheme_windows(s, 11).collect();
        let expected: Vec<&str> = vec!["abcdefghijk", "bcdefghijkl"];
        assert_eq!(result, expected);
    }

    #[test]
    fn umlauts() {
        let s = "äöüáyz";
        let result: Vec<&str> = grapheme_windows(s, 3).collect();
        let expected: Vec<&str> = vec!["äöü", "öüá", "üáy", "áyz"];
        assert_eq!(result, expected);
    }
    #[test]
    fn graphemes() {
        let s = "a\r\nb🇷🇺🇸🇹";
        let result: Vec<&str> = grapheme_windows(s, 3).collect();

        let expected: Vec<&str> = vec!["a\r\nb", "\r\nb🇷🇺", "b🇷🇺🇸🇹"];
        assert_eq!(result, expected);
    }
}
