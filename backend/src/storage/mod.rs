mod local;

pub use local::LocalFileStorage;

use std::pin::Pin;
use std::sync::Arc;

/// Future type returned by [`ImageStorage`] trait methods.
///
/// `async fn` in traits is not `dyn`-compatible in edition 2024 without an
/// explicit `BoxFuture`-style return position. We keep `Arc<dyn ImageStorage>`
/// for dyn-compat and a future object-store plug-in, so each method returns a
/// boxed future.
pub type StorageFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Abstraction for image storage backends.
///
/// The methods return [`StorageFuture`] to keep the trait `dyn`-compatible
/// after dropping the `#[async_trait]` macro in edition 2024. The same shape
/// is used by the Repository pattern introduced in Phase 2-5.
pub trait ImageStorage: Send + Sync {
    /// Upload image bytes and return the public URL.
    fn upload<'a>(
        &'a self,
        bytes: &'a [u8],
        filename: &'a str,
        content_type: &'a str,
    ) -> StorageFuture<'a, Result<String, StorageError>>;

    /// Delete a previously uploaded image by its URL or key.
    fn delete<'a>(&'a self, url: &'a str) -> StorageFuture<'a, Result<(), StorageError>>;
}

#[derive(Debug)]
pub enum StorageError {
    Io(String),
}

impl std::fmt::Display for StorageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StorageError::Io(msg) => write!(f, "IO error: {}", msg),
        }
    }
}

impl std::error::Error for StorageError {}

/// Build the local image storage backend.
///
/// Reads `UPLOAD_DIR` (default `./uploads`). Only local filesystem storage is
/// supported; a former Firebase/GCS path was removed (issue #458).
pub fn create_storage() -> Arc<dyn ImageStorage> {
    if let Ok(backend) = std::env::var("IMAGE_STORAGE")
        && backend != "local"
    {
        tracing::warn!("IMAGE_STORAGE={backend} is no longer supported; using local storage only");
    }
    let upload_dir = std::env::var("UPLOAD_DIR").unwrap_or_else(|_| "./uploads".to_string());
    Arc::new(LocalFileStorage::new(upload_dir))
}
