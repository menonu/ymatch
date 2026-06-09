use crate::error::AppError;
use crate::generated::ymatch::*;
use axum::{Json, extract::State};
use sqlx::{PgPool, Row};

#[derive(serde::Deserialize)]
pub struct SearchQuery {
    pub q: String,
}

pub async fn global_search(
    State(pool): State<PgPool>,
    axum::extract::Query(query): axum::extract::Query<SearchQuery>,
) -> Result<Json<Vec<SearchResult>>, AppError> {
    let search_term = format!("%{}%", query.q);
    let mut results = Vec::new();

    let event_rows = sqlx::query(
        "SELECT id, name FROM events WHERE name ILIKE $1 AND status = 'published' LIMIT 10",
    )
    .bind(&search_term)
    .fetch_all(&pool)
    .await?;

    for row in event_rows {
        results.push(SearchResult {
            r#type: "event".to_string(),
            id: row.get("id"),
            title: row.get("name"),
            subtitle: None,
            photo_url: None,
            event_id: row.get("id"),
        });
    }

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
    .fetch_all(&pool)
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

    Ok(Json(results))
}
