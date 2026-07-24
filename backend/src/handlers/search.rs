//! Global search handler. Phase 5 of #163 splits this into:
//! - thin handler (parse + assemble `SearchResult`s)
//! - [`crate::repositories::event::EventRepository::search`]
//! - [`crate::repositories::merch::MerchandiseRepository::search`]

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::routes::AppState;
use axum::{Json, extract::State};

#[derive(serde::Deserialize)]
pub struct SearchQuery {
    pub q: String,
}

pub async fn global_search(
    State(state): State<AppState>,
    axum::extract::Query(query): axum::extract::Query<SearchQuery>,
) -> Result<Json<Vec<SearchResult>>, AppError> {
    let search_term = format!("%{}%", query.q);
    let mut results = Vec::new();

    // Events
    for (id, name) in state.events.search(&search_term, 10).await? {
        results.push(SearchResult {
            r#type: "event".to_string(),
            id,
            title: name,
            subtitle: None,
            photo_url: None,
            event_id: id,
        });
    }

    // Merchandise
    for hit in state.merch.search(&search_term, 20).await? {
        let subtitle = if let Some(gn) = hit.group_name {
            format!("{} > {}", hit.event_name, gn)
        } else {
            hit.event_name
        };
        results.push(SearchResult {
            r#type: "item".to_string(),
            id: hit.id,
            title: hit.name,
            subtitle: Some(subtitle),
            photo_url: hit.photo_url,
            event_id: hit.event_id,
        });
    }

    Ok(Json(results))
}
