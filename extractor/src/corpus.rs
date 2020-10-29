use ouroboros::self_referencing;
use std::fs;

#[self_referencing]
pub struct Corpus {
    file_string: String,
    #[borrows(file_string)]
    lines: Vec<&'this str>,
}

impl Corpus {
    pub fn from_file(filename: &str) -> Corpus {
        println!("loading {}...", filename);
        let file_string: String = fs::read_to_string(filename).unwrap();
        let corpus = CorpusBuilder {
            file_string: file_string,
            lines_builder: |file_string| file_string.lines().collect(),
        }
        .build();
        corpus.with_lines(|lines| println!("{} lines", lines.len()));
        corpus
    }
}
