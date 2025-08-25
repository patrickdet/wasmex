use rustler::{Atom, Encoder, Env, Error, LocalPid, ResourceArc, Term};
use std::sync::MutexGuard;
use wasmtime::component::{Instance, ResourceAny, Val};
use wasmtime::Store;

use crate::atoms;
use crate::component_type_conversion::{convert_params, encode_result_with_store};
use crate::store::{ComponentStoreData, ComponentStoreResource};
use crate::wasi_resource::WasiResourceWrapper;

/// Call a method on a resource
// #[rustler::nif(name = "resource_call_method", schedule = "DirtyCpu")]
pub fn resource_call_method<'a>(
    env: Env<'a>,
    store_resource: ResourceArc<ComponentStoreResource>,
    resource_wrapper: ResourceArc<WasiResourceWrapper>,
    method_name: String,
    params: Vec<Term<'a>>,
    from: Term<'a>,
) -> Term<'a> {
    // Validate that the resource belongs to this store
    let store: MutexGuard<Store<ComponentStoreData>> = store_resource.inner.lock().unwrap();
    let store_id = store.data().store_id;
    
    if resource_wrapper.store_id != store_id {
        let error_msg = "Resource does not belong to this store".to_string();
        let error_tuple = env.error_tuple(error_msg);
        return rustler::types::tuple::make_tuple(
            env,
            &[
                atoms::returned_function_call().encode(env),
                error_tuple,
                from,
            ],
        );
    }

    // TODO: Implement actual method dispatch
    // This requires:
    // 1. Looking up the resource type definition
    // 2. Finding the method signature
    // 3. Converting parameters
    // 4. Calling the method
    // 5. Converting and returning results
    
    let error_msg = "Resource method dispatch not yet implemented".to_string();
    let error_tuple = env.error_tuple(error_msg);
    rustler::types::tuple::make_tuple(
        env,
        &[
            atoms::returned_function_call().encode(env),
            error_tuple,
            from,
        ],
    )
}

/// Create a new resource instance (constructor)
// #[rustler::nif(name = "resource_new", schedule = "DirtyCpu")]
pub fn resource_new<'a>(
    env: Env<'a>,
    store_resource: ResourceArc<ComponentStoreResource>,
    resource_type_path: Vec<String>,
    params: Vec<Term<'a>>,
    from: Term<'a>,
) -> Term<'a> {
    // TODO: Implement resource constructor
    // This requires:
    // 1. Looking up the resource type
    // 2. Finding the constructor signature
    // 3. Converting parameters
    // 4. Calling the constructor
    // 5. Creating a WasiResourceWrapper
    // 6. Registering it with the store's resource registry
    // 7. Returning the wrapped resource
    
    let error_msg = "Resource constructor not yet implemented".to_string();
    let error_tuple = env.error_tuple(error_msg);
    rustler::types::tuple::make_tuple(
        env,
        &[
            atoms::returned_function_call().encode(env),
            error_tuple,
            from,
        ],
    )
}

/// Drop a resource and unregister it from the registry
pub fn drop_resource_internal(
    store: &mut Store<ComponentStoreData>,
    resource_wrapper: &WasiResourceWrapper,
) -> Result<(), String> {
    // Get the resource from the wrapper
    let resource_any = resource_wrapper.inner.lock().map_err(|e| {
        format!("Could not lock resource: {}", e.to_string())
    })?;

    // Drop the resource in the store context
    resource_any.resource_drop(store).map_err(|e| {
        format!("Failed to drop resource: {}", e.to_string())
    })?;

    // TODO: Remove from resource registry
    // store.data().resource_registry.remove_resource(resource_id);

    Ok(())
}