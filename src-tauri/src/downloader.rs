/**
 * @license
 * Copyright 2025 a7mddra
 * SPDX-License-Identifier: Apache-2.0
 */

use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use futures_util::StreamExt;

const RELEASES_URL: &str = "https://github.com/a7mddra/spatialshot/releases/latest/download";

#[derive(Debug, Clone)]
pub struct DownloadEvent {
    pub component: String,
    pub percent: u64,
    pub status: String,
}

pub fn get_artifact_url(component: &str) -> String {
    let os_suffix = if cfg!(target_os = "windows") {
        "-win-x64.zip"
    } else if cfg!(target_os = "linux") {
        "-linux-x64.zip"
    } else if cfg!(target_os = "macos") {
        if cfg!(target_arch = "aarch64") {
            "-mac-arm64.zip"
        } else {
            "-mac-x64.zip"
        }
    } else {
        "unknown"
    };

    // e.g., https://.../engine-win-x64.zip
    format!("{}/{}{}", RELEASES_URL, component, os_suffix)
}

pub async fn download_file<F>(
    url: &str, 
    dest_path: &PathBuf, 
    component_name: &str,
    on_progress: F
) -> Result<(), String> 
where F: Fn(DownloadEvent) + Send + 'static 
{
    println!("[Internal] Starting download: {}", url);

    let mut file = File::create(dest_path).map_err(|e| format!("Failed to create file: {}", e))?;

    let client = reqwest::Client::new();
    let res = client.get(url).send().await.map_err(|e| format!("Network error: {}", e))?;

    if !res.status().is_success() {
        return Err(format!("Server returned: {}", res.status()));
    }

    let total_size = res.content_length().unwrap_or(0);
    let mut downloaded: u64 = 0;
    let mut stream = res.bytes_stream();

    while let Some(item) = stream.next().await {
        let chunk = item.map_err(|e| format!("Chunk error: {}", e))?;
        file.write_all(&chunk).map_err(|e| format!("Write error: {}", e))?;

        downloaded += chunk.len() as u64;

        if total_size > 0 {
            let percent = (downloaded * 100) / total_size;
            on_progress(DownloadEvent {
                component: component_name.to_string(),
                percent,
                status: "downloading".to_string(),
            });
        }
    }

    on_progress(DownloadEvent {
        component: component_name.to_string(),
        percent: 100,
        status: "done".to_string(),
    });

    Ok(())
}
