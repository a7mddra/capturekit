use std::path::PathBuf;

#[cfg(target_os = "windows")]
use winreg::enums::*;
#[cfg(target_os = "windows")]
use winreg::RegKey;

pub fn finalize_install(install_dir: &PathBuf) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let path = Path::new("Software").join("Microsoft").join("Windows").join("CurrentVersion").join("Uninstall").join("Spatialshot");
        let (key, _) = hkcu.create_subkey(&path).map_err(|e| e.to_string())?;
        
        let exe_path = install_dir.join("spatialshot-orchestrator.exe");
        let uninstall_cmd = format!("\"{}\" --uninstall", exe_path.to_string_lossy());

        key.set_value("DisplayName", &"Spatialshot").map_err(|e| e.to_string())?;
        key.set_value("UninstallString", &uninstall_cmd).map_err(|e| e.to_string())?;
        key.set_value("Publisher", &"a7mddra").map_err(|e| e.to_string())?;
        // Create Desktop Shortcut (Requires separate crate 'mslink' or PowerShell invocation)
        // For now, we skip shortcut creation to keep dependencies low, or use powershell cmd
    }
    Ok(())
}

// Dummy for non-windows to make compiler happy
#[cfg(not(target_os = "windows"))]
pub fn finalize_install(_: &PathBuf) -> Result<(), String> { Ok(()) }