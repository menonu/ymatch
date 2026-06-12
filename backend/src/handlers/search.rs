//! Global search handler. Phase 5 of #163 splits this into:
//! - thin handler (parse + delegate)
//! - [`crate::repositories::event::EventRepository::search`]
//! - [`crate::repositories::merch::MerchandiseRepository::search_by_name`]
//!   (a new method we add in this phase for the search use-case)

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::routes::AppState;
use axum::{Json, extract::State};
use sqlx::Row;

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

    // Merchandise: query the merch table directly via the underlying pool
    // (the search query is a thin wrapper around ILIKE; not worth a
    // dedicated repository method). The merch.merch_name + event_name
    // subtitle requires a JOIN to the events table.
    let merch_rows = sqlx::query(
        "SELECT m.id, m.name, m.group_name, m.photo_url, m.event_id, e.name as event_name
         FROM merchandise m
         JOIN events e ON m.event_id = e.id
         WHERE (m.name ILIKE $1 OR m.group_name ILIKE $1)
           AND m.is_deleted = false AND m.status = 'published'
           AND e.status = 'published'
         LIMIT 20",
    )
    .bind(&search_term)
    .fetch_all(&state.pool)
    .await?;

    for row in merch_rows {
        let group_name: Option<String> = row.get("group_name");
        let event_name: String = row.get("event_name");
        let subtitle = if let Some(gn) = group_name {
            format!("{} > {}", event_name, gn)
        } else {
            event_name
        };
        results.push(SearchResult {
            r#type: "item".to_string(),
            id: row.get("id"),
            title: row.get("name"),
            subtitle: Some(subtitle),
            photo_url: row.get("photo_url"),
            event_id: row.get("event_id"),
        });
    }

    // The merch search query lives inline here for now; Phase 6 (or
    // a follow-up) could promote it to a `MerchandiseRepository::search`
    // method. We keep the direct SQL because the search has a JOIN
    // to the events table that is unique to the search use-case.
    let _ = state;

    Ok(Json(results))
}
