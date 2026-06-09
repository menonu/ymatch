use super::{ImageStorage, StorageError, StorageFuture};
use std::path::PathBuf;
use tokio::fs;

pub struct LocalFileStorage {
    upload_dir: PathBuf,
}

impl LocalFileStorage {
    pub fn new(upload_dir: String) -> Self {
        let path = PathBuf::from(&upload_dir);
        // Ensure the directory exists at construction time (best-effort)
        std::fs::create_dir_all(&path).ok();
        Self { upload_dir: path }
    }
}

impl ImageStorage for LocalFileStorage {
    fn upload<'a>(
        &'a self,
        bytes: &'a [u8],
        filename: &'a str,
        _content_type: &'a str,
    ) -> StorageFuture<'a, Result<String, StorageError>> {
        Box::pin(async move {
            let file_path = self.upload_dir.join(filename);
            fs::write(&file_path, bytes)
                .await
                .map_err(|e| StorageError::Io(e.to_string()))?;

            // Return relative path — resolved to full URL by the handler
            Ok(format!("uploads/{}", filename))
        })
    }

    fn delete<'a>(&'a self, url: &'a str) -> StorageFuture<'a, Result<(), StorageError>> {
        Box::pin(async move {
            // Extract filename from URL or relative path
            let filename = url
                .rsplit('/')
                .next()
                .ok_or_else(|| StorageError::Io("Invalid URL".to_string()))?;
            let file_path = self.upload_dir.join(filename);
            if file_path.exists() {
                fs::remove_file(&file_path)
                    .await
                    .map_err(|e| StorageError::Io(e.to_string()))?;
            }
            Ok(())
        })
    }
}
