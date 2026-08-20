use std::{env, fs, path::PathBuf};

const PLATFORM_MESSAGE_FILES: [&str; 3] = ["Drive.msg", "DriveFeedback.msg", "Feedback.msg"];

fn main() {
    let manifest_directory = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let output_directory = PathBuf::from(env::var("OUT_DIR").unwrap());

    let staged_share = output_directory.join("msg_share");
    let staged_msg_directory = staged_share.join("robot_platform_msgs/msg");
    fs::create_dir_all(&staged_msg_directory).unwrap();
    for file_name in PLATFORM_MESSAGE_FILES {
        let source = manifest_directory.join("interfaces/msg").join(file_name);
        println!("cargo:rerun-if-changed={}", source.display());
        fs::copy(&source, staged_msg_directory.join(file_name)).unwrap();
    }

    let config = oxidros_build::msg::Config::builder()
        .packages(&["robot_platform_msgs", "std_msgs", "builtin_interfaces"])
        .extra_search_path(staged_share)
        .extra_search_path(manifest_directory.join(".pixi/envs/default/share"))
        .build();
    oxidros_build::msg::generate_msgs_with_config(&config);
}
