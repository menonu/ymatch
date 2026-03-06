use tracing::info;

pub async fn send_match_notification(device_token: &str, partner_username: &str) {
    info!(
        "🔔 [PUSH NOTIFICATION] To: {}, Message: 'You have a new match with {}! Check it out in the Trades tab.'",
        device_token, partner_username
    );

    // In a real implementation, we would call an external service like FCM or APNs here.
}
