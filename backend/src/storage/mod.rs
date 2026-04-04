mod firebase;
mod local;

pub use firebase::FirebaseStorage;
pub use local::LocalFileStorage;

use std::sync::Arc;

/// Abstraction for image storage backends.
#[async_trait::async_trait]
pub trait ImageStorage: Send + Sync {
    /// Upload image bytes and return the public URL.
    async fn upload(
        &self,
        bytes: &[u8],
        filename: &str,
        content_type: &str,
    ) -> Result<String, StorageError>;
    /// Delete a previously uploaded image by its URL or key.
    async fn delete(&self, url: &str) -> Result<(), StorageError>;
}

#[derive(Debug)]
pub enum StorageError {
    Io(String),
    Remote(String),
}

impl std::fmt::Display for StorageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StorageError::Io(msg) => write!(f, "IO error: {}", msg),
            StorageError::Remote(msg) => write!(f, "Remote error: {}", msg),
        }
    }
}

/// Build an ImageStorage backend based on the IMAGE_STORAGE env var.
pub async fn create_storage() -> Arc<dyn ImageStorage> {
    let backend = std::env::var("IMAGE_STORAGE").unwrap_or_else(|_| "local".to_string());
    match backend.as_str() {
        "firebase" => {
            let bucket = std::env::var("FIREBASE_STORAGE_BUCKET")
                .expect("FIREBASE_STORAGE_BUCKET must be set when IMAGE_STORAGE=firebase");
            Arc::new(
                FirebaseStorage::new(bucket)
                    .await
                    .expect("Failed to initialize Firebase Storage"),
            )
        }
        _ => {
            let upload_dir =
                std::env::var("UPLOAD_DIR").unwrap_or_else(|_| "./uploads".to_string());
            Arc::new(LocalFileStorage::new(upload_dir))
        }
    }
}
