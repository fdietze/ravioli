use ouroboros::self_referencing;
use std::fs;
use std::iter;
use unicode_segmentation::UnicodeSegmentation;

#[self_referencing]
pub struct Corpus {
    file_string: String,
    #[borrows(file_string)]
    lines: Vec<(&'this str, Vec<usize>)>,
    total_characters: usize,
}

impl Corpus {
    pub fn from_file(filename: &str) -> Corpus {
        println!("loading {}...", filename);
        let file_string: String = fs::read_to_string(filename).unwrap();
        let total_characters = file_string.graphemes(true).count();
        let corpus = CorpusBuilder {
            file_string: file_string,
            total_characters: total_characters,
            lines_builder: |file_string| {
                file_string
                    .lines()
                    .map(|line| {
                        (
                            line,
                            line.grapheme_indices(true)
                                .map(|(i, _)| i)
                                .chain(iter::once(line.len()))
                                .collect(),
                        )
                    })
                    .collect()
            },
        }
        .build();
        corpus
            .with_lines(|lines| println!("{} lines, {} characters", lines.len(), total_characters));
        corpus
    }
}
