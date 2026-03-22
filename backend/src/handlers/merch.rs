use crate::generated::ymatch::*;
use axum::{extract::Path, extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

pub async fn list_all_merch(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<Merchandise>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, event_id, name, photo_url, group_name, sort_order FROM merchandise ORDER BY id ASC")
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let merch = rows
        .into_iter()
        .map(|row| Merchandise {
            id: row.get("id"),
            event_id: row.get("event_id"),
            name: row.get("name"),
            photo_url: row.get("photo_url"),
            group_name: row.get("group_name"),
            sort_order: row.get::<Option<i32>, _>("sort_order"),
        })
        .collect();

    Ok(Json(merch))
}

pub async fn list_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
) -> Result<Json<Vec<Merchandise>>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT id, event_id, name, photo_url, group_name, sort_order FROM merchandise WHERE event_id = $1 ORDER BY sort_order ASC, id ASC")
        .bind(event_id)
        .fetch_all(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let merch = rows
        .into_iter()
        .map(|row| Merchandise {
            id: row.get("id"),
            event_id: row.get("event_id"),
            name: row.get("name"),
            photo_url: row.get("photo_url"),
            group_name: row.get("group_name"),
            sort_order: Some(row.get("sort_order")),
        })
        .collect();

    Ok(Json(merch))
}

pub async fn create_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateMerchRequest>,
) -> Result<Json<Merchandise>, (StatusCode, String)> {
    let row = sqlx::query(
        "INSERT INTO merchandise (event_id, name, photo_url, group_name) VALUES ($1, $2, $3, $4) RETURNING id, event_id, name, photo_url, group_name, sort_order"
    )
    .bind(event_id)
    .bind(payload.name)
    .bind(payload.photo_url)
    .bind(payload.group_name)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(Merchandise {
        id: row.get("id"),
        event_id: row.get("event_id"),
        name: row.get("name"),
        photo_url: row.get("photo_url"),
        group_name: row.get("group_name"),
        sort_order: Some(row.get("sort_order")),
    }))
}

pub async fn update_merch_sort_order(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<UpdateMerchSortOrderRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    if payload.event_id != event_id {
        return Err((StatusCode::BAD_REQUEST, "Event ID mismatch".to_string()));
    }

    let mut tx = pool
        .begin()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    for (merch_id, sort_order) in payload.sort_orders {
        sqlx::query("UPDATE merchandise SET sort_order = $1 WHERE id = $2 AND event_id = $3")
            .bind(sort_order)
            .bind(merch_id)
            .bind(event_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    tx.commit()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}
