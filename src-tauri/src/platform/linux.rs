use std::fs;
use std::path::PathBuf;
use std::os::unix::fs::PermissionsExt;

// 1. EMBED THE SCRIPTS (Assuming they are in packages/installer/scripts for now, or root)
// NOTE: Adjust paths if your scripts are elsewhere.
const UNINSTALL_SCRIPT: &str = include_str!("../../../../../scripts/APPVER.py"); // Placeholder for real script
const HOTKEY_SCRIPT: &str = "#!/bin/bash\n echo 'Dummy Hotkey Script'"; // Replace with include_str! later
const APP_ICON: &[u8] = include_bytes!("../../icons/icon_linux.png"); 

pub fn finalize_install(install_dir: &PathBuf) -> Result<(), String> {
    let home = dirs::home_dir().ok_or("Cannot find home directory")?;
    
    // 1. Install Icon
    let icon_dir = home.join(".local/share/icons/hicolor/512x512/apps");
    fs::create_dir_all(&icon_dir).map_err(|e| e.to_string())?;
    let icon_path = icon_dir.join("spatialshot.png");
    fs::write(&icon_path, APP_ICON).map_err(|e| e.to_string())?;

    // 2. Create .desktop file
    let desktop_content = format!(r#"[Desktop Entry]
Version=1.0
Type=Application
Name=Spatialshot
Exec={}/spatialshot-orchestrator
Icon=spatialshot
Terminal=false
Categories=Utility;
"#, install_dir.to_string_lossy());
    
    let desktop_path = home.join(".local/share/applications/spatialshot.desktop");
    fs::write(desktop_path, desktop_content).map_err(|e| e.to_string())?;

    // 3. Create CLI Wrapper
    let bin_dir = home.join(".local/bin");
    fs::create_dir_all(&bin_dir).map_err(|e| e.to_string())?;
    let wrapper_path = bin_dir.join("spatialshot");
    
    let wrapper_content = format!(r#"#!/bin/bash
if [ "$1" == "uninstall" ]; then
    echo "Uninstalling..."
    rm -rf "{}"
    rm -f "$HOME/.local/share/applications/spatialshot.desktop"
    rm -f "$HOME/.local/bin/spatialshot"
else
    "{}/spatialshot-orchestrator" "$@"
fi
"#, install_dir.to_string_lossy(), install_dir.to_string_lossy());

    fs::write(&wrapper_path, wrapper_content).map_err(|e| e.to_string())?;
    fs::set_permissions(&wrapper_path, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;

    Ok(())
}