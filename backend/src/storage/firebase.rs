use super::{ImageStorage, StorageError};
use std::sync::Arc;

/// Firebase Storage (Google Cloud Storage) backend.
/// Uses the GCS JSON API with Application Default Credentials via gcp_auth.
pub struct FirebaseStorage {
    bucket: String,
    client: reqwest::Client,
    auth: Arc<dyn gcp_auth::TokenProvider>,
}

impl FirebaseStorage {
    pub async fn new(bucket: String) -> Result<Self, StorageError> {
        let auth = gcp_auth::provider()
            .await
            .map_err(|e| StorageError::Remote(format!("Failed to init GCP auth: {}", e)))?;
        Ok(Self {
            bucket,
            client: reqwest::Client::new(),
            auth,
        })
    }

    async fn get_access_token(&self) -> Result<String, StorageError> {
        let scopes = &["https://www.googleapis.com/auth/devstorage.read_write"];
        let token = self
            .auth
            .token(scopes)
            .await
            .map_err(|e| StorageError::Remote(format!("Failed to get token: {}", e)))?;
        Ok(token.as_str().to_string())
    }
}

#[async_trait::async_trait]
impl ImageStorage for FirebaseStorage {
    async fn upload(
        &self,
        bytes: &[u8],
        filename: &str,
        content_type: &str,
    ) -> Result<String, StorageError> {
        let token = self.get_access_token().await?;

        let upload_url = format!(
            "https://storage.googleapis.com/upload/storage/v1/b/{}/o?uploadType=media&name=images/{}",
            self.bucket, filename
        );

        let resp = self
            .client
            .post(&upload_url)
            .header("Authorization", format!("Bearer {}", token))
            .header("Content-Type", content_type)
            .body(bytes.to_vec())
            .send()
            .await
            .map_err(|e| StorageError::Remote(format!("Upload failed: {}", e)))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(StorageError::Remote(format!(
                "Upload returned {}: {}",
                status, body
            )));
        }

        // Public URL via Google Cloud Storage
        let public_url = format!(
            "https://storage.googleapis.com/{}/images/{}",
            self.bucket, filename
        );
        Ok(public_url)
    }

    async fn delete(&self, url: &str) -> Result<(), StorageError> {
        let object_name = if url.contains("/o/") {
            let after_o = url.split("/o/").nth(1).unwrap_or("");
            let name = after_o.split('?').next().unwrap_or(after_o);
            urlencoding::decode(name)
                .map(|s| s.to_string())
                .unwrap_or_else(|_| name.to_string())
        } else {
            return Err(StorageError::Remote(
                "Cannot parse object name from URL".to_string(),
            ));
        };

        let token = self.get_access_token().await?;
        let delete_url = format!(
            "https://storage.googleapis.com/storage/v1/b/{}/o/{}",
            self.bucket,
            urlencoding::encode(&object_name)
        );

        let resp = self
            .client
            .delete(&delete_url)
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .await
            .map_err(|e| StorageError::Remote(format!("Delete failed: {}", e)))?;

        if !resp.status().is_success() && resp.status().as_u16() != 404 {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(StorageError::Remote(format!(
                "Delete returned {}: {}",
                status, body
            )));
        }

        Ok(())
    }
}
