use std::{env, fs, path::PathBuf};

const PLATFORM_MESSAGE_FILES: [&str; 3] = ["Drive.msg", "DriveFeedback.msg", "Feedback.msg"];

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    let staged_share = out_dir.join("msg_share");
    let staged_msg_dir = staged_share.join("robot_platform_msgs/msg");
    fs::create_dir_all(&staged_msg_dir).unwrap();
    for file_name in PLATFORM_MESSAGE_FILES {
        let source = manifest_dir.join("msgs/msg").join(file_name);
        println!("cargo:rerun-if-changed={}", source.display());
        fs::copy(&source, staged_msg_dir.join(file_name)).unwrap();
    }

    let config = oxidros_build::msg::Config::builder()
        .packages(&["robot_platform_msgs", "std_msgs", "builtin_interfaces"])
        .extra_search_path(staged_share)
        .extra_search_path(manifest_dir.join(".pixi/envs/default/share"))
        .build();
    oxidros_build::msg::generate_msgs_with_config(&config);
}
