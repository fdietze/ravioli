use std::env;
use std::fs::File;
use std::io::{prelude::*, BufReader};
use tokenizers::models::bpe::{BpeTrainerBuilder, BPE};
use tokenizers::normalizers::{strip::Strip, unicode::NFC, utils::Sequence};
use tokenizers::pre_tokenizers::byte_level::ByteLevel;
use tokenizers::pre_tokenizers::whitespace::Whitespace;
use tokenizers::tokenizer::Tokenizer;
use tokenizers::{Result, TokenizerBuilder};

fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    let corpus_file = &args[1];

    let trainer = BpeTrainerBuilder::new()
        .show_progress(true)
        // .vocab_size(vocab_size)
        .min_frequency(10)
        // .special_tokens(vec![
        //     AddedToken::from(String::from("<s>"), true),
        //     AddedToken::from(String::from("<pad>"), true),
        //     AddedToken::from(String::from("</s>"), true),
        //     AddedToken::from(String::from("<unk>"), true),
        //     AddedToken::from(String::from("<mask>"), true),
        // ])
        .build();

    let tokenizer = TokenizerBuilder::new()
        .with_model(BPE::default())
        .with_normalizer(Some(Sequence::new(vec![NFC.into()])))
        .with_pre_tokenizer(Some(ByteLevel::default()))
        .with_post_processor(Some(ByteLevel::default()))
        .with_decoder(Some(ByteLevel::default()))
        .build()?;

    let pretty = false;
    let tokenizer_file = format!("{}.tokenizer.json", corpus_file.to_string());
    tokenizer
        .train(&trainer, vec![corpus_file.to_string()])?
        .save(&tokenizer_file, pretty)?;

    // encode example
    let mut tokenizer = Tokenizer::from_file(&tokenizer_file).unwrap();
    tokenizer.with_pre_tokenizer(Whitespace::default());

    // let example = "Ich geh lieber wieder an die Arbeit.";
    let example = "Über Nacht kostet 50 Cent.";

    println!("{:?}", tokenizer.encode(example, true).unwrap());

    // let file = File::open(corpus_file.to_string())?;
    // let reader = BufReader::new(file);

    // for line in reader.lines() {
    //     println!(
    //         "{}",
    //         tokenizer
    //             .encode(line?, false)
    //             .unwrap()
    //             .get_tokens()
    //             .join(" ")
    //     );
    // }

    Ok(())
}
