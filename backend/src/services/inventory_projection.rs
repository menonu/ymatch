//! Provisional inventory projection for in-progress trades (#427).
//!
//! `GET /api/v1/user/:id/inventory` returns both the DB `quantity` and a
//! `projected_quantity` after every contributing match settles. Deltas follow
//! default apply ([`super::match_lifecycle`] / ADR 0009) plus a display-only
//! WANT decrement for the receiver.
//!
//! Negative projected values are **allowed** (not clamped). A future offer /
//! accept warning can treat `projected < 0` as over-commit; preview that
//! warning with [`accumulate_projection_deltas`] `exclude_match_id` + `overlay`
//! (replace this match's on-table legs with a hypothetical proposal).
//!
//! This module is proto-aware only for [`attach_projected_quantities`]. The
//! accumulator itself is a pure function of legs.

use crate::generated::ymatch::InventoryItem;
use std::collections::{HashMap, HashSet};

pub const STATUS_HAVE: &str = "HAVE";
pub const STATUS_WANT: &str = "WANT";
pub const STATUS_TRADE: &str = "TRADE";

/// One on-table (or hypothetical) match leg that can move projected qty.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProjectionLeg {
    pub match_id: i32,
    pub merch_id: i32,
    pub giver_user_id: i32,
    pub quantity: i32,
}

/// Merch metadata for synthetic `quantity = 0` inventory rows.
#[derive(Clone, Debug, Default)]
pub struct ProjectionMerch {
    pub merch_name: Option<String>,
    pub photo_url: Option<String>,
    pub group_name: Option<String>,
    pub is_deleted: Option<bool>,
}

/// `(merch_id, status)` → signed delta to add to DB quantity.
pub type ProjectionDeltas = HashMap<(i32, &'static str), i32>;

/// Per-leg display deltas for `user_id` (default apply + WANT display).
///
/// - Giver: `HAVE −qty`, `TRADE −qty`
/// - Receiver: `HAVE +qty`, `WANT −qty` (WANT is display-only; apply does not
///   change WANT)
///
/// Zero / negative `qty` contribute nothing. `skip_have_decrement` is
/// apply-time only and is never reflected here.
pub fn projection_leg_deltas(
    user_id: i32,
    giver_user_id: i32,
    qty: i32,
) -> Vec<(&'static str, i32)> {
    if qty <= 0 {
        return Vec::new();
    }
    if giver_user_id == user_id {
        vec![(STATUS_HAVE, -qty), (STATUS_TRADE, -qty)]
    } else {
        vec![(STATUS_HAVE, qty), (STATUS_WANT, -qty)]
    }
}

/// Sum merch×status deltas for `user_id`.
///
/// `exclude_match_id` drops that match's current legs (counter-offer /
/// accept preview). `overlay` is then applied as if those legs were on the
/// table. List inventory uses `exclude_match_id = None` and an empty overlay.
pub fn accumulate_projection_deltas(
    user_id: i32,
    legs: &[ProjectionLeg],
    exclude_match_id: Option<i32>,
    overlay: &[ProjectionLeg],
) -> ProjectionDeltas {
    let mut out = ProjectionDeltas::new();
    for leg in legs {
        if exclude_match_id == Some(leg.match_id) {
            continue;
        }
        add_leg(&mut out, user_id, leg);
    }
    for leg in overlay {
        add_leg(&mut out, user_id, leg);
    }
    out.retain(|_, delta| *delta != 0);
    out
}

fn add_leg(out: &mut ProjectionDeltas, user_id: i32, leg: &ProjectionLeg) {
    for (status, delta) in projection_leg_deltas(user_id, leg.giver_user_id, leg.quantity) {
        *out.entry((leg.merch_id, status)).or_insert(0) += delta;
    }
}

/// Write `projected_quantity` onto every row (`quantity + delta`).
///
/// Statuses that have a non-zero delta but no inventory row get a synthetic
/// `quantity = 0` row so the UI can show `0(n)` (typical: receiver HAVE).
pub fn attach_projected_quantities(
    items: &mut Vec<InventoryItem>,
    user_id: i32,
    deltas: &ProjectionDeltas,
    merch: &HashMap<i32, ProjectionMerch>,
) {
    let mut seen: HashSet<(i32, &'static str)> = HashSet::new();
    let mut from_items: HashMap<i32, ProjectionMerch> = HashMap::new();

    for item in items.iter_mut() {
        from_items
            .entry(item.merch_id)
            .or_insert_with(|| ProjectionMerch {
                merch_name: item.merch_name.clone(),
                photo_url: item.photo_url.clone(),
                group_name: item.group_name.clone(),
                is_deleted: item.is_deleted,
            });
        let status = match item.status.as_str() {
            STATUS_HAVE => STATUS_HAVE,
            STATUS_WANT => STATUS_WANT,
            STATUS_TRADE => STATUS_TRADE,
            _ => {
                item.projected_quantity = Some(item.quantity);
                continue;
            }
        };
        let delta = deltas.get(&(item.merch_id, status)).copied().unwrap_or(0);
        item.projected_quantity = Some(item.quantity + delta);
        seen.insert((item.merch_id, status));
    }

    for ((merch_id, status), delta) in deltas {
        if seen.contains(&(*merch_id, *status)) {
            continue;
        }
        let meta = merch.get(merch_id).or_else(|| from_items.get(merch_id));
        items.push(InventoryItem {
            id: 0,
            user_id,
            merch_id: *merch_id,
            status: (*status).to_string(),
            quantity: 0,
            merch_name: meta
                .and_then(|m| m.merch_name.clone())
                .or_else(|| Some(String::new())),
            photo_url: meta.and_then(|m| m.photo_url.clone()),
            group_name: meta.and_then(|m| m.group_name.clone()),
            is_deleted: meta.and_then(|m| m.is_deleted),
            projected_quantity: Some(*delta),
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn leg(match_id: i32, merch_id: i32, giver: i32, qty: i32) -> ProjectionLeg {
        ProjectionLeg {
            match_id,
            merch_id,
            giver_user_id: giver,
            quantity: qty,
        }
    }

    fn get(d: &ProjectionDeltas, merch: i32, status: &'static str) -> i32 {
        d.get(&(merch, status)).copied().unwrap_or(0)
    }

    #[test]
    fn giver_decrements_have_and_trade() {
        assert_eq!(
            projection_leg_deltas(1, 1, 3),
            vec![(STATUS_HAVE, -3), (STATUS_TRADE, -3)]
        );
    }

    #[test]
    fn receiver_increments_have_and_decrements_want() {
        assert_eq!(
            projection_leg_deltas(2, 1, 3),
            vec![(STATUS_HAVE, 3), (STATUS_WANT, -3)]
        );
    }

    #[test]
    fn non_positive_qty_is_noop() {
        assert!(projection_leg_deltas(1, 1, 0).is_empty());
        assert!(projection_leg_deltas(1, 1, -2).is_empty());
    }

    #[test]
    fn accumulate_giver_and_receiver_across_matches() {
        // Match 10: user 1 gives merch 1 x1; match 11: user 1 receives merch 2 x2.
        let deltas =
            accumulate_projection_deltas(1, &[leg(10, 1, 1, 1), leg(11, 2, 2, 2)], None, &[]);
        assert_eq!(get(&deltas, 1, STATUS_HAVE), -1);
        assert_eq!(get(&deltas, 1, STATUS_TRADE), -1);
        assert_eq!(get(&deltas, 2, STATUS_HAVE), 2);
        assert_eq!(get(&deltas, 2, STATUS_WANT), -2);
        assert!(!deltas.contains_key(&(1, STATUS_WANT)));
        assert!(!deltas.contains_key(&(2, STATUS_TRADE)));
    }

    #[test]
    fn accumulate_sums_same_merch_status() {
        let deltas =
            accumulate_projection_deltas(1, &[leg(10, 1, 1, 1), leg(11, 1, 1, 2)], None, &[]);
        assert_eq!(get(&deltas, 1, STATUS_TRADE), -3);
        assert_eq!(get(&deltas, 1, STATUS_HAVE), -3);
    }

    #[test]
    fn accumulate_allows_negative_overcommit() {
        // Two give-1 legs against a single unit of stock still sum to -2.
        let deltas =
            accumulate_projection_deltas(1, &[leg(10, 1, 1, 1), leg(11, 1, 1, 1)], None, &[]);
        assert_eq!(get(&deltas, 1, STATUS_TRADE), -2);
    }

    #[test]
    fn overlay_replaces_excluded_match_legs() {
        // On-table match 10 gives merch 1 x1. Counter-offer preview: give x2.
        let on_table = [leg(10, 1, 1, 1), leg(10, 2, 2, 1)];
        let overlay = [leg(10, 1, 1, 2), leg(10, 2, 2, 2)];
        let deltas = accumulate_projection_deltas(1, &on_table, Some(10), &overlay);
        assert_eq!(get(&deltas, 1, STATUS_TRADE), -2);
        assert_eq!(get(&deltas, 1, STATUS_HAVE), -2);
        assert_eq!(get(&deltas, 2, STATUS_HAVE), 2);
        assert_eq!(get(&deltas, 2, STATUS_WANT), -2);
    }

    #[test]
    fn overlay_without_exclude_would_double_count() {
        // Document the preview contract: callers must exclude the match they
        // are replacing. Adding overlay on top of the same match is -1 + -2.
        let on_table = [leg(10, 1, 1, 1)];
        let overlay = [leg(10, 1, 1, 2)];
        let deltas = accumulate_projection_deltas(1, &on_table, None, &overlay);
        assert_eq!(get(&deltas, 1, STATUS_TRADE), -3);
    }

    #[test]
    fn attach_sets_projected_and_synthesizes_missing_row() {
        let mut items = vec![InventoryItem {
            id: 7,
            user_id: 1,
            merch_id: 10,
            status: STATUS_TRADE.to_string(),
            quantity: 2,
            merch_name: Some("Card".into()),
            photo_url: None,
            group_name: Some("G".into()),
            is_deleted: Some(false),
            projected_quantity: None,
        }];
        let mut deltas = ProjectionDeltas::new();
        deltas.insert((10, STATUS_TRADE), -1);
        deltas.insert((10, STATUS_HAVE), -1);
        let mut merch = HashMap::new();
        merch.insert(
            10,
            ProjectionMerch {
                merch_name: Some("Card".into()),
                photo_url: None,
                group_name: Some("G".into()),
                is_deleted: Some(false),
            },
        );
        attach_projected_quantities(&mut items, 1, &deltas, &merch);

        let trade = items
            .iter()
            .find(|i| i.status == STATUS_TRADE)
            .expect("trade row");
        assert_eq!(trade.quantity, 2);
        assert_eq!(trade.projected_quantity, Some(1));

        let have = items
            .iter()
            .find(|i| i.status == STATUS_HAVE)
            .expect("synthetic have");
        assert_eq!(have.id, 0);
        assert_eq!(have.quantity, 0);
        assert_eq!(have.projected_quantity, Some(-1));
        assert_eq!(have.merch_name.as_deref(), Some("Card"));
    }

    #[test]
    fn attach_equal_when_no_delta() {
        let mut items = vec![InventoryItem {
            id: 1,
            user_id: 1,
            merch_id: 3,
            status: STATUS_WANT.to_string(),
            quantity: 4,
            merch_name: Some("X".into()),
            photo_url: None,
            group_name: None,
            is_deleted: None,
            projected_quantity: None,
        }];
        attach_projected_quantities(&mut items, 1, &ProjectionDeltas::new(), &HashMap::new());
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].projected_quantity, Some(4));
    }
}
