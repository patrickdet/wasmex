use rustler::{Encoder, Env, Error, NifResult, ResourceArc, Term};
use std::sync::Mutex;
use wasmtime::component::{ResourceAny, Val};
use wasmtime::Store;

use crate::atoms;
use crate::store::{ComponentStoreData, ComponentStoreResource};
use crate::wasi_resource::{ResourceType, WasiResourceWrapper};

/// Represents a host-defined resource that delegates method calls to Elixir
#[derive(Debug, Clone)]
pub struct HostResource {
    /// Unique ID for this resource instance
    pub resource_id: u64,
    /// The WIT type name (e.g., "database-connection")
    pub type_name: String,
    /// Store ID this resource belongs to
    pub store_id: usize,
}

impl HostResource {
    pub fn new(resource_id: u64, type_name: String, store_id: usize) -> Self {
        HostResource {
            resource_id,
            type_name,
            store_id,
        }
    }
}

/// NIF to create a new host resource
#[rustler::nif(name = "host_resource_new")]
pub fn host_resource_new(
    store_resource: ResourceArc<ComponentStoreResource>,
    resource_id: u64,
    type_name: String,
) -> NifResult<ResourceArc<WasiResourceWrapper>> {
    let mut store = store_resource.inner.lock().map_err(|e| {
        Error::Term(Box::new(format!(
            "Could not lock store: {}",
            e.to_string()
        )))
    })?;

    let store_id = store.data().store_id;

    // Create the host resource
    let host_resource = HostResource::new(resource_id, type_name.clone(), store_id);

    // Create a ResourceAny that wraps our host resource
    // This will require implementing the necessary traits for wasmtime
    // For now, we'll create a placeholder that can be expanded
    
    // Note: In a full implementation, we'd need to:
    // 1. Define a custom resource type in wasmtime
    // 2. Register it with the component model
    // 3. Implement method dispatch that calls back to Elixir
    
    // For now, we'll create a simplified version that demonstrates the concept
    // The actual wasmtime integration would require more complex trait implementations
    
    // Create a dummy ResourceAny for demonstration
    // In production, this would be a proper wasmtime resource
    let resource_any = create_host_resource_any(host_resource, &mut *store)?;

    // Wrap it in our WasiResourceWrapper
    let wrapper = WasiResourceWrapper {
        inner: Mutex::new(resource_any),
        resource_type: ResourceType::HostDefined {
            type_name: type_name.clone(),
        },
        is_owned: true,
        store_id,
    };

    Ok(ResourceArc::new(wrapper))
}

/// Creates a ResourceAny for a host resource
/// 
/// This is a placeholder implementation. In a full implementation, this would:
/// 1. Create a proper wasmtime Resource
/// 2. Register it with the component model
/// 3. Set up method dispatch callbacks
fn create_host_resource_any(
    _host_resource: HostResource,
    _store: &mut Store<ComponentStoreData>,
) -> NifResult<ResourceAny> {
    // This is a simplified placeholder
    // A full implementation would require:
    // - Defining a custom wasmtime::component::Resource implementation
    // - Registering callbacks for method dispatch
    // - Setting up proper type information
    
    Err(Error::Term(Box::new(
        "Host resource creation not yet fully implemented - requires wasmtime Resource trait implementation".to_string()
    )))
}

/// Dispatch a method call from WASM to a host resource in Elixir
/// 
/// This function is called by wasmtime when a WASM component invokes a method
/// on a host-defined resource. It bridges the call to Elixir code.
pub fn dispatch_host_method(
    env: Env,
    _resource_id: u64,
    _method_name: String,
    params: Vec<Val>,
) -> NifResult<Val> {
    // Convert wasmtime Val parameters to Elixir terms
    let _elixir_params = convert_vals_to_terms(env, params)?;
    
    // Call the Elixir host resource manager
    // Note: In a real implementation, this would use message passing or callbacks
    // For now, we'll return a placeholder error
    Err(Error::Term(Box::new(
        "Host resource method dispatch not fully implemented".to_string()
    )))
}

/// Convert wasmtime Val values to Elixir terms
fn convert_vals_to_terms(env: Env, vals: Vec<Val>) -> NifResult<Vec<Term>> {
    vals.into_iter()
        .map(|val| val_to_term(env, val))
        .collect()
}

/// Convert a single wasmtime Val to an Elixir term
fn val_to_term(env: Env, val: Val) -> NifResult<Term> {
    match val {
        Val::Bool(b) => Ok(b.encode(env)),
        Val::S8(i) => Ok(i.encode(env)),
        Val::U8(i) => Ok(i.encode(env)),
        Val::S16(i) => Ok(i.encode(env)),
        Val::U16(i) => Ok(i.encode(env)),
        Val::S32(i) => Ok(i.encode(env)),
        Val::U32(i) => Ok(i.encode(env)),
        Val::S64(i) => Ok(i.encode(env)),
        Val::U64(i) => Ok(i.encode(env)),
        Val::Float32(f) => Ok(f.encode(env)),
        Val::Float64(f) => Ok(f.encode(env)),
        Val::String(s) => Ok(s.encode(env)),
        Val::List(list) => {
            let terms: NifResult<Vec<Term>> = list
                .iter()
                .map(|v| val_to_term(env, v.clone()))
                .collect();
            Ok(terms?.encode(env))
        }
        Val::Record(fields) => {
            // Create a map from the fields
            let mut map = rustler::types::map::map_new(env);
            for (field_name, field_val) in fields.iter() {
                let value = val_to_term(env, field_val.clone())?;
                map = map.map_put(field_name.encode(env), value).unwrap();
            }
            Ok(map.encode(env))
        }
        Val::Option(opt) => match opt {
            Some(v) => {
                let inner = val_to_term(env, *v)?;
                Ok(rustler::types::tuple::make_tuple(
                    env,
                    &[atoms::some().encode(env), inner],
                ))
            }
            None => Ok(atoms::none().encode(env)),
        },
        Val::Result(res) => match res {
            Ok(Some(v)) => {
                let inner = val_to_term(env, *v)?;
                Ok(rustler::types::tuple::make_tuple(
                    env,
                    &[atoms::ok().encode(env), inner],
                ))
            }
            Ok(None) => Ok(rustler::types::tuple::make_tuple(
                env,
                &[atoms::ok().encode(env), atoms::nil().encode(env)],
            )),
            Err(Some(v)) => {
                let inner = val_to_term(env, *v)?;
                Ok(rustler::types::tuple::make_tuple(
                    env,
                    &[atoms::error().encode(env), inner],
                ))
            }
            Err(None) => Ok(rustler::types::tuple::make_tuple(
                env,
                &[atoms::error().encode(env), atoms::nil().encode(env)],
            )),
        },
        _ => Err(Error::Term(Box::new(format!(
            "Unsupported Val type: {:?}",
            val
        )))),
    }
}

/// Convert an Elixir term back to a wasmtime Val
fn convert_term_to_val(_env: Env, _term: Term) -> NifResult<Val> {
    // This would implement the reverse conversion from Elixir terms to wasmtime Val
    // For now, return a placeholder error
    Err(Error::Term(Box::new(
        "Term to Val conversion not yet implemented".to_string()
    )))
}

/// Handle dropping a host resource
pub fn drop_host_resource(resource_id: u64) -> NifResult<()> {
    // This would call back to Elixir to drop the resource
    // Implementation would involve message passing or registered callbacks
    
    // For now, log that we're dropping
    eprintln!("Dropping host resource: {}", resource_id);
    
    Ok(())
}