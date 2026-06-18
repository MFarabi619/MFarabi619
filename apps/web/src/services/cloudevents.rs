use crate::api::CloudEvent;
use reqwest::Error;

pub struct CloudEventsService;

impl CloudEventsService {
    pub async fn fetch(url: &str) -> Result<Vec<CloudEvent>, Error> {
        reqwest::get(format!("{url}/api/cloudevents"))
            .await?
            .json()
            .await
    }
}