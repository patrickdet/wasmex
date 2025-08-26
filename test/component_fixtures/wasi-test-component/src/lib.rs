#![cfg(target_os = "wasi")]

wit_bindgen::generate!({
    path: "wit",
    world: "wasi-test",
});

use exports::test::wasi_component::wasi_tests::Guest;
use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use std::env;
use std::io::{self, Write};

struct Component;

impl Guest for Component {
    fn test_filesystem_write(path: String, content: String) -> Result<u32, String> {
        fs::write(&path, &content)
            .map_err(|e| format!("Failed to write file: {}", e))?;
        Ok(content.len() as u32)
    }
    
    fn test_filesystem_read(path: String) -> Result<String, String> {
        fs::read_to_string(&path)
            .map_err(|e| format!("Failed to read file: {}", e))
    }
    
    fn test_filesystem_delete(path: String) -> Result<(), String> {
        fs::remove_file(&path)
            .map_err(|e| format!("Failed to delete file: {}", e))
    }
    
    fn test_filesystem_exists(path: String) -> bool {
        Path::new(&path).exists()
    }
    
    fn test_filesystem_list_dir(path: String) -> Result<Vec<String>, String> {
        let dir_path = if path.is_empty() || path == "." {
            Path::new(".")
        } else {
            Path::new(&path)
        };
        
        let entries = fs::read_dir(dir_path)
            .map_err(|e| format!("Failed to read directory: {}", e))?;
        
        let mut names = Vec::new();
        for entry in entries {
            let entry = entry.map_err(|e| format!("Failed to read entry: {}", e))?;
            let name = entry.file_name()
                .into_string()
                .map_err(|_| "Invalid UTF-8 in filename".to_string())?;
            names.push(name);
        }
        
        Ok(names)
    }
    
    fn test_random_bytes(len: u32) -> Vec<u8> {
        // Use a simple PRNG for deterministic testing, or read from /dev/random in real WASI
        let mut bytes = vec![0u8; len as usize];
        
        // In WASI, we can use getrandom (which std uses internally)
        if let Ok(_) = getrandom::getrandom(&mut bytes) {
            bytes
        } else {
            // Fallback to a simple pseudo-random generator
            for i in 0..len as usize {
                bytes[i] = ((i * 7 + 13) % 256) as u8;
            }
            bytes
        }
    }
    
    fn test_random_u64() -> u64 {
        let bytes = Self::test_random_bytes(8);
        u64::from_le_bytes([
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
        ])
    }
    
    fn test_clock_now() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos() as u64
    }
    
    fn test_clock_resolution() -> u64 {
        // Typical resolution is 1 microsecond (1000 nanoseconds)
        // This is platform-dependent
        1000
    }
    
    fn test_get_env(key: String) -> Option<String> {
        env::var(&key).ok()
    }
    
    fn test_get_args() -> Vec<String> {
        env::args().collect()
    }
    
    fn test_print_stdout(message: String) -> Result<(), String> {
        print!("{}", message);
        io::stdout().flush()
            .map_err(|e| format!("Failed to flush stdout: {}", e))
    }
    
    fn test_print_stderr(message: String) -> Result<(), String> {
        eprint!("{}", message);
        io::stderr().flush()
            .map_err(|e| format!("Failed to flush stderr: {}", e))
    }
}

export!(Component);