/**
 * @license
 * Copyright 2025 a7mddra
 * SPDX-License-Identifier: Apache-2.0
 */

use tauri::{AppHandle, Emitter, Manager};
use std::path::PathBuf;

mod downloader;
mod setup;
mod platform;

#[tauri::command]
async fn start_installation(window: tauri::Window, _app_handle: AppHandle) -> Result<(), String> {
    // 1. Resolve Path
    let install_path = setup::resolve_install_path();
    
    // 2. Wipe Previous
    setup::nuke_previous_version(&install_path)?;
    std::fs::create_dir_all(&install_path).map_err(|e| e.to_string())?;

    // 3. Download List
    let components = vec!["kernel", "engine", "spatialshot"];
    
    // 4. Loop Components
    for component in components {
        let url = downloader::get_artifact_url(component);
        let temp_zip = std::env::temp_dir().join(format!("spatialshot-{}.zip", component));
        
        // A. Download
        downloader::download_file(&url, &temp_zip, component, |event| {
             window.emit("progress", event).unwrap();
        }).await?;

        // B. Extract
        setup::extract_and_install(&window, &temp_zip, &install_path, component).await?;
    }

    // 5. OS Finalization (Icons, Desktop Files, Registers)
    #[cfg(target_os = "linux")]
    platform::linux::finalize_install(&install_path)?;

    #[cfg(target_os = "windows")]
    platform::windows::finalize_install(&install_path)?;
    
    #[cfg(target_os = "macos")]
    platform::macos::finalize_install(&install_path)?;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![start_installation])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}