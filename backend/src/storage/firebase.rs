use super::{ImageStorage, StorageError};

/// Firebase Storage (Google Cloud Storage) backend.
/// Uses the GCS JSON API with default credentials (ADC) or service account.
pub struct FirebaseStorage {
    bucket: String,
    client: reqwest::Client,
}

impl FirebaseStorage {
    pub fn new(bucket: String) -> Self {
        Self {
            bucket,
            client: reqwest::Client::new(),
        }
    }

    /// Get access token from the GCE metadata server (works on Cloud Run).
    async fn get_access_token(&self) -> Result<String, StorageError> {
        let url = "http://metadata.google.internal/computeMetadata/v1/instance/service-account/default/token";
        let resp = self
            .client
            .get(url)
            .header("Metadata-Flavor", "Google")
            .send()
            .await
            .map_err(|e| StorageError::Remote(format!("Failed to get token: {}", e)))?;

        let body: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| StorageError::Remote(format!("Failed to parse token: {}", e)))?;

        body.get("access_token")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .ok_or_else(|| StorageError::Remote("No access_token in response".to_string()))
    }
}

#[async_trait::async_trait]
impl ImageStorage for FirebaseStorage {
    async fn upload(&self, bytes: &[u8], filename: &str, content_type: &str) -> Result<String, StorageError> {
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

        // Public URL for the uploaded object
        let public_url = format!(
            "https://firebasestorage.googleapis.com/v0/b/{}/o/images%2F{}?alt=media",
            self.bucket, filename
        );
        Ok(public_url)
    }

    async fn delete(&self, url: &str) -> Result<(), StorageError> {
        // Extract the object path from the Firebase Storage URL
        let object_name = if url.contains("/o/") {
            // URL like: .../o/images%2Ffilename.jpg?alt=media
            let after_o = url.split("/o/").nth(1).unwrap_or("");
            let name = after_o.split('?').next().unwrap_or(after_o);
            urlencoding::decode(name)
                .map(|s| s.to_string())
                .unwrap_or_else(|_| name.to_string())
        } else {
            return Err(StorageError::Remote("Cannot parse object name from URL".to_string()));
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
