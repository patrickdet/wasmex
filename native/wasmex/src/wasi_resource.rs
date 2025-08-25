use rustler::{Error, NifResult, ResourceArc};
use std::sync::Mutex;
use wasmtime::component::{ResourceAny, Val};

#[derive(Debug, Clone)]
pub enum ResourceType {
    GuestDefined { type_name: String },
    HostDefined { type_name: String },
}

pub struct WasiResourceWrapper {
    pub inner: Mutex<ResourceAny>,
    pub resource_type: ResourceType,
    pub is_owned: bool,
    pub store_id: usize, // Link to the store that owns this resource
}

#[rustler::resource_impl()]
impl rustler::Resource for WasiResourceWrapper {}

#[rustler::nif(name = "resource_drop")]
pub fn resource_drop(
    resource: ResourceArc<WasiResourceWrapper>,
    store_resource: ResourceArc<crate::store::ComponentStoreResource>,
) -> NifResult<rustler::Atom> {
    let mut store = store_resource.inner.lock().map_err(|e| {
        Error::Term(Box::new(format!(
            "Could not lock store: {}",
            e.to_string()
        )))
    })?;

    // Validate that the resource belongs to this store
    if resource.store_id != store.data().store_id {
        return Err(Error::Term(Box::new(
            "Resource does not belong to this store".to_string()
        )));
    }

    let resource_any = resource.inner.lock().map_err(|e| {
        Error::Term(Box::new(format!(
            "Could not lock resource: {}",
            e.to_string()
        )))
    })?;

    // Drop the resource in the store context
    resource_any.resource_drop(&mut *store).map_err(|e| {
        Error::Term(Box::new(format!(
            "Failed to drop resource: {}",
            e.to_string()
        )))
    })?;

    Ok(crate::atoms::ok())
}

impl WasiResourceWrapper {
    pub fn new(resource: ResourceAny, store_id: usize) -> Self {
        let is_owned = resource.owned();
        
        // Determine resource type based on whether it's host or guest
        // For now, we'll default to guest-defined until we can properly detect
        let resource_type = ResourceType::GuestDefined {
            type_name: "unknown".to_string(), // TODO: Get actual type name from resource metadata
        };

        WasiResourceWrapper {
            inner: Mutex::new(resource),
            resource_type,
            is_owned,
            store_id,
        }
    }

    pub fn is_owned(&self) -> bool {
        self.is_owned
    }

    pub fn store_id(&self) -> usize {
        self.store_id
    }
}

pub fn val_to_resource_wrapper(
    val: Val,
    store_id: usize,
) -> Result<ResourceArc<WasiResourceWrapper>, String> {
    match val {
        Val::Resource(resource_any) => {
            let wrapper = WasiResourceWrapper::new(resource_any, store_id);
            Ok(ResourceArc::new(wrapper))
        }
        _ => Err("Expected a resource value".to_string()),
    }
}

pub fn resource_wrapper_to_val(
    wrapper: &ResourceArc<WasiResourceWrapper>,
) -> Result<Val, String> {
    let resource = wrapper.inner.lock().map_err(|e| {
        format!("Could not lock resource: {}", e.to_string())
    })?;
    
    // Clone the ResourceAny - this is safe as it just clones the handle
    Ok(Val::Resource(resource.clone()))
}