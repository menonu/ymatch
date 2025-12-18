use std::io::Result;
use std::path::PathBuf;

fn main() -> Result<()> {
    let mut config = prost_build::Config::new();

    // Setup paths
    let root = PathBuf::from("/workspace");
    let proto_file = root.join("proto/models.proto");
    let out_dir = root.join("backend/src/generated");

    println!("Generating Rust code from {:?} to {:?}", proto_file, out_dir);

    // Ensure output directory exists
    std::fs::create_dir_all(&out_dir)?;

    config.out_dir(&out_dir);

    // Add Serde support to all generated models
    config.type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]");
    config.type_attribute(".", "#[serde(rename_all = \"snake_case\")]");

    config.compile_protos(&[proto_file], &[root.join("proto")])?;

    // Create mod.rs in generated directory
    let mod_file = out_dir.join("mod.rs");
    std::fs::write(mod_file, "pub mod ymatch {\n    include!(\"ymatch.rs\");\n}\n")?;

    Ok(())
}
