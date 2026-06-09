use axum::{Json, http::StatusCode};

pub async fn get_system_status() -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let rev = option_env!("GIT_HASH").unwrap_or("unknown");

    let mut sys = sysinfo::System::new_all();
    sys.refresh_all();

    let total_memory = sys.total_memory();
    let used_memory = sys.used_memory();
    let cpu_usage: f32 = sys.cpus().iter().map(|cpu| cpu.cpu_usage()).sum::<f32>()
        / (sys.cpus().len() as f32).max(1.0);
    let uptime = sysinfo::System::uptime();

    Ok(Json(serde_json::json!({
        "backend_version": rev,
        "resources": {
            "total_memory_bytes": total_memory,
            "used_memory_bytes": used_memory,
            "cpu_usage_percent": cpu_usage,
            "uptime_seconds": uptime,
            "os_name": sysinfo::System::name().unwrap_or_else(|| "Unknown".to_string()),
            "os_version": sysinfo::System::os_version().unwrap_or_else(|| "Unknown".to_string()),
        }
    })))
}
