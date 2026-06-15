use std::io::Result;
use std::path::PathBuf;

fn main() -> Result<()> {
    // Setup paths
    let root = PathBuf::from("/workspace");
    let proto_file = root.join("proto/models.proto");
    let proto_root = root.join("proto");
    let out_dir = root.join("backend/src/generated");

    println!(
        "Generating Rust code from {:?} to {:?}",
        proto_file, out_dir
    );

    // Ensure output directory exists
    std::fs::create_dir_all(&out_dir)?;

    let descriptor_path = out_dir.join("proto_descriptor.bin");

    // Generate prost structs and a FileDescriptorSet for pbjson.
    prost_build::Config::new()
        .out_dir(&out_dir)
        .file_descriptor_set_path(&descriptor_path)
        .compile_protos(&[proto_file], &[proto_root])?;

    // Generate spec-compliant proto3 JSON serde impls.
    let descriptor_set = std::fs::read(&descriptor_path)?;
    pbjson_build::Builder::new()
        .out_dir(&out_dir)
        .register_descriptors(&descriptor_set)?
        .build(&[".ymatch"])?;

    // Create mod.rs in generated directory.
    // pbjson produces `<package>.serde.rs` with Serialize/Deserialize impls
    // for the types defined in the matching `<package>.rs`.
    let mod_file = out_dir.join("mod.rs");
    std::fs::write(
        mod_file,
        "pub mod ymatch {\n    include!(\"ymatch.rs\");\n    include!(\"ymatch.serde.rs\");\n}\n",
    )?;

    // The descriptor set is only needed during generation.
    let _ = std::fs::remove_file(&descriptor_path);

    Ok(())
}
