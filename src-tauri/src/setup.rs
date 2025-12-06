/**
 * @license
 * Copyright 2025 a7mddra
 * SPDX-License-Identifier: Apache-2.0
 */

use std::fs;
use std::path::{Path, PathBuf};
use tauri::{Emitter, Window};
use zip::ZipArchive;

#[derive(Clone, serde::Serialize)]
struct ProgressPayload {
    component: String,
    percent: u64,
    status: String,
}

pub fn resolve_install_path() -> PathBuf {
    // 1. Determine Standard OS Install Paths
    if cfg!(target_os = "windows") {
        // %LOCALAPPDATA%/Programs/Spatialshot
        dirs::data_local_dir()
            .unwrap()
            .join("Programs")
            .join("Spatialshot")
    } else if cfg!(target_os = "macos") {
        // /Applications/Spatialshot.app
        PathBuf::from("/Applications/Spatialshot.app")
    } else {
        // ~/.local/share/spatialshot
        dirs::data_local_dir()
            .unwrap()
            .join("spatialshot")
    }
}

pub fn nuke_previous_version(install_path: &Path) -> Result<(), String> {
    if !install_path.exists() {
        return Ok(());
    }

    // SAFETY CHECK: Never delete root or home
    if install_path == dirs::home_dir().unwrap() || install_path == Path::new("/") {
        return Err("Safety Warning: Attempted to delete critical system path.".into());
    }

    println!("Cleaning up previous installation at: {:?}", install_path);
    fs::remove_dir_all(install_path).map_err(|e| format!("Failed to delete old version: {}", e))
}

pub async fn extract_and_install(
    window: &Window,
    zip_path: &PathBuf,
    install_path: &PathBuf,
    component: &str
) -> Result<(), String> {
    
    let file = fs::File::open(zip_path).map_err(|e| e.to_string())?;
    let mut archive = ZipArchive::new(file).map_err(|e| e.to_string())?;

    let total_files = archive.len();
    
    for i in 0..total_files {
        let mut file = archive.by_index(i).map_err(|e| e.to_string())?;
        
        // Determine extraction target
        // For macOS, we might need to map "engine/" to "Contents/Resources/Engine/"
        // For now, we extract flat to the target structure
        let outpath = match file.enclosed_name() {
            Some(path) => install_path.join(path),
            None => continue,
        };

        if (*file.name()).ends_with('/') {
            fs::create_dir_all(&outpath).map_err(|e| e.to_string())?;
        } else {
            if let Some(p) = outpath.parent() {
                if !p.exists() {
                    fs::create_dir_all(p).map_err(|e| e.to_string())?;
                }
            }
            let mut outfile = fs::File::create(&outpath).map_err(|e| e.to_string())?;
            std::io::copy(&mut file, &mut outfile).map_err(|e| e.to_string())?;
        }

        // Emit Progress every 10 files to keep UI snappy
        if i % 10 == 0 {
            let percent = ((i as f64 / total_files as f64) * 100.0) as u64;
            window.emit("progress", ProgressPayload {
                component: component.to_string(),
                percent,
                status: "extracting".to_string(),
            }).unwrap_or(());
        }

        // UNIX: Restore Permissions (chmod +x)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if let Some(mode) = file.unix_mode() {
                fs::set_permissions(&outpath, fs::Permissions::from_mode(mode))
                    .map_err(|e| e.to_string())?;
            }
        }
    }

    Ok(())
}