use crate::api::FileEntry;
use reqwest::Error;

pub struct FileService;

impl FileService {
    pub async fn list(base_url: &str, location: &str) -> Result<Vec<FileEntry>, Error> {
        reqwest::get(format!("{base_url}/api/filesystem/{location}"))
            .await?
            .json()
            .await
    }

    pub async fn upload(
        base_url: &str,
        location: &str,
        filename: &str,
        data: &[u8],
    ) -> Result<reqwest::Response, Error> {
        let part = reqwest::multipart::Part::bytes(data.to_vec())
            .file_name(filename.to_string());
        let form = reqwest::multipart::Form::new()
            .part("file", part);
        reqwest::Client::new()
            .put(format!("{base_url}/api/filesystem/{location}/{filename}"))
            .multipart(form)
            .send()
            .await
    }

    pub async fn delete(
        base_url: &str,
        location: &str,
        path: &str,
    ) -> Result<reqwest::Response, Error> {
        reqwest::Client::new()
            .delete(format!("{base_url}/api/filesystem/{location}/{path}"))
            .send()
            .await
    }
}