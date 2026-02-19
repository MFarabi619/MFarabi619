use mdbook_gen::generate_router_build_script;
use std::{env::current_dir, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-changed=./src/content/docs/src");
    generate_mdbook_router("./src/content/docs", "src/content/docs");
}

fn generate_mdbook_router(mdbook_dir: impl Into<PathBuf>, out_dir: impl Into<PathBuf>) {
    let mdbook_dir = mdbook_dir.into();
    let out_dir = current_dir().expect("cwd").join(out_dir.into());

    let mut out = generate_router_build_script(mdbook_dir);
    out.push_str("\nuse super::*;\n");

    std::fs::create_dir_all(&out_dir).expect("create output dir");
    std::fs::write(out_dir.join("router.rs"), out).expect("write generated router");
}
