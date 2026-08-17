use std::path::PathBuf;

use fetch_source::{load_sources, Cache};

const RGPIO_SOURCES: [&str; 5] = ["rgpio.c", "lgCfg.c", "lgErr.c", "lgDbg.c", "lgMD5.c"];

fn main() {
    println!("cargo:rerun-if-changed=Cargo.toml");

    let manifest_directory = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let output_directory = PathBuf::from(std::env::var("OUT_DIR").unwrap());

    let mut cache = Cache::load_or_create(&output_directory).expect("open fetch-source cache");
    let (name, source) = load_sources(&manifest_directory)
        .expect("read fetch-source metadata")
        .into_iter()
        .next()
        .expect("a fetch-source entry");

    let lg_directory = if cache.items().contains(&source) {
        cache.items().get(&source).unwrap().path().to_path_buf()
    } else {
        let dest = cache
            .cache_dir()
            .append(cache.items().relative_path(&source));
        let artefact = source
            .fetch(&*dest)
            .unwrap_or_else(|err| panic!("failed to fetch {name}: {err}"));
        let path = artefact.path().to_path_buf();
        cache.items_mut().insert(artefact);
        cache.save().expect("save fetch-source cache");
        path
    };

    let rgpio_source = manifest_directory.join("src").join("rgpio");
    cc::Build::new()
        .include(&rgpio_source)
        .include(&lg_directory)
        .flag("-include")
        .flag(rgpio_source.join("portability.h").to_str().unwrap())
        .files(RGPIO_SOURCES.iter().map(|file| lg_directory.join(file)))
        .warnings(false)
        .compile("rgpio");

    println!("cargo:rustc-link-lib=pthread");
}
