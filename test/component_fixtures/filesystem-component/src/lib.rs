#![cfg(target_os = "wasi")]

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

wit_bindgen::generate!({
    path: "wit",
    world: "filesystem-test",
});

use crate::exports::test::filesystem::types::{
    Guest as TypesGuest, GuestDirectory, GuestFileHandle, FileHandle, Directory,
};

struct Component;

pub struct MyFileHandle {
    content: Arc<Mutex<Vec<u8>>>,
    position: Arc<Mutex<usize>>,
}

pub struct MyDirectory {
    files: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

impl MyDirectory {
    fn new() -> Self {
        MyDirectory {
            files: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

impl GuestFileHandle for MyFileHandle {
    fn read(&self, length: u32) -> Result<Vec<u8>, String> {
        let content = self.content.lock().map_err(|e| e.to_string())?;
        let mut pos = self.position.lock().map_err(|e| e.to_string())?;
        
        let start = *pos;
        let end = std::cmp::min(start + length as usize, content.len());
        
        if start >= content.len() {
            return Ok(Vec::new());
        }
        
        let data = content[start..end].to_vec();
        *pos = end;
        
        Ok(data)
    }

    fn write(&self, data: Vec<u8>) -> Result<u32, String> {
        let mut content = self.content.lock().map_err(|e| e.to_string())?;
        let mut pos = self.position.lock().map_err(|e| e.to_string())?;
        
        let start = *pos;
        let written = data.len();
        
        if start + written > content.len() {
            content.resize(start + written, 0);
        }
        content[start..start + written].copy_from_slice(&data);
        *pos = start + written;
        
        Ok(written as u32)
    }

    fn close(&self) {
        // Nothing to do for now
    }
}

impl GuestDirectory for MyDirectory {
    fn create_file(&self, name: String) -> Result<FileHandle, String> {
        let mut files = self.files.lock().map_err(|e| e.to_string())?;
        files.insert(name, Vec::new());
        
        let handle = MyFileHandle {
            content: Arc::new(Mutex::new(Vec::new())),
            position: Arc::new(Mutex::new(0)),
        };
        
        Ok(FileHandle::new(handle))
    }

    fn list_files(&self) -> Vec<String> {
        let files = self.files.lock().unwrap();
        files.keys().cloned().collect()
    }
}

impl TypesGuest for Component {
    type FileHandle = MyFileHandle;
    type Directory = MyDirectory;
    
    fn create_test_directory() -> Directory {
        Directory::new(MyDirectory::new())
    }
}

export!(Component);