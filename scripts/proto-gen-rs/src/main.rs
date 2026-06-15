use regex::Regex;
use std::io::Result;
use std::path::PathBuf;

fn to_camel_case(s: &str) -> String {
    let mut parts = s.split('_').peekable();
    let mut out = String::new();
    while let Some(part) = parts.next() {
        if out.is_empty() {
            out.push_str(part);
        } else if part.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) {
            // Preserve numbers as-is when they appear after an underscore,
            // e.g. user1_id -> user1Id.
            out.push_str(part);
        } else {
            let mut chars = part.chars();
            if let Some(first) = chars.next() {
                out.push(first.to_ascii_uppercase());
                out.extend(chars);
            }
        }
    }
    out
}

fn add_camelcase_aliases(content: &str) -> String {
    // Matches a prost field attribute followed by its `pub name:` declaration.
    let re = Regex::new(r"(?m)^(\s*)(#\[prost\([^]]+\)\])\n(\s*)pub (\w+):").unwrap();
    re.replace_all(content, |caps: &regex::Captures| {
        let indent = &caps[1];
        let prost_attr = &caps[2];
        let field_indent = &caps[3];
        let field_name = &caps[4];
        if field_name.contains('_') {
            let alias = to_camel_case(field_name);
            format!(
                "{indent}#[serde(alias = \"{alias}\")]\n{indent}{prost_attr}\n{field_indent}pub {field_name}:"
            )
        } else {
            caps[0].to_string()
        }
    })
    .to_string()
}

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

    // Add Serde support to all generated models. Keep snake_case as the
    // canonical JSON shape (matches existing integration tests) and add
    // camelCase aliases so the Flutter frontend's proto3 JSON payloads
    // (`toProto3Json()` / `mergeFromProto3Json()`) also deserialize.
    config.type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]");
    config.type_attribute(".", "#[serde(rename_all = \"snake_case\")]");

    config.compile_protos(&[proto_file], &[root.join("proto")])?;

    // Post-process the generated file to accept proto3 JSON (camelCase) keys
    // while keeping snake_case as the canonical serialization format.
    let generated = out_dir.join("ymatch.rs");
    let content = std::fs::read_to_string(&generated)?;
    let updated = add_camelcase_aliases(&content);
    std::fs::write(&generated, updated)?;

    // Create mod.rs in generated directory
    let mod_file = out_dir.join("mod.rs");
    std::fs::write(mod_file, "pub mod ymatch {\n    include!(\"ymatch.rs\");\n}\n")?;

    Ok(())
}
