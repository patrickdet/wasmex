use rustler::{Encoder, Env, OwnedEnv, ResourceArc, Term};
use std::thread;
use wasmtime::component::Val;
use wasmtime::Store;

use crate::atoms;
use crate::component_instance::ComponentInstanceResource;
use crate::component_type_conversion::{convert_params, vals_to_terms_with_store};
use crate::store::{ComponentStoreData, ComponentStoreResource};
use crate::wasi_resource::WasiResourceWrapper;
use rustler::env::SavedTerm;
use rustler::types::tuple::make_tuple;

/// Call a method on a resource
#[rustler::nif(name = "resource_call_method", schedule = "DirtyCpu")]
pub fn resource_call_method<'a>(
    env: Env<'a>,
    store_resource: ResourceArc<ComponentStoreResource>,
    instance_resource: ResourceArc<ComponentInstanceResource>,
    resource_wrapper: ResourceArc<WasiResourceWrapper>,
    interface_path: Vec<String>,
    method_name: String,
    params: Vec<Term<'a>>,
    from: Term<'a>,
) -> Term<'a> {
    // Spawn thread to handle async execution
    let pid = env.pid();
    let mut thread_env = OwnedEnv::new();
    let saved_params = thread_env.save(params);
    let saved_from = thread_env.save(from);
    
    thread::spawn(move || {
        thread_env.send_and_clear(&pid, |thread_env| {
            execute_resource_method(
                thread_env,
                store_resource,
                instance_resource,
                resource_wrapper,
                interface_path,
                method_name,
                saved_params,
                saved_from,
            )
        })
    });
    
    atoms::ok().encode(env)
}

fn execute_resource_method(
    env: Env,
    store_resource: ResourceArc<ComponentStoreResource>,
    instance_resource: ResourceArc<ComponentInstanceResource>,
    resource_wrapper: ResourceArc<WasiResourceWrapper>,
    interface_path: Vec<String>,
    method_name: String,
    saved_params: SavedTerm,
    saved_from: SavedTerm,
) -> Term {
    let from = saved_from.load(env).decode::<Term>().unwrap_or_else(|_| {
        "could not load 'from' param".encode(env)
    });
    
    // Validate that the resource belongs to this store
    let mut store = store_resource.inner.lock().unwrap();
    let store_id = store.data().store_id;
    
    if resource_wrapper.store_id != store_id {
        let error_msg = "Resource does not belong to this store".to_string();
        let error_tuple = env.error_tuple(error_msg);
        return make_tuple(
            env,
            &[
                atoms::returned_function_call().encode(env),
                error_tuple,
                from,
            ],
        );
    }
    
    // Load the params
    let params = match saved_params.load(env).decode::<Vec<Term>>() {
        Ok(p) => p,
        Err(err) => {
            let error_msg = format!("Could not load params: {:?}", err);
            let error_tuple = env.error_tuple(error_msg);
            return make_tuple(
                env,
                &[
                    atoms::returned_function_call().encode(env),
                    error_tuple,
                    from,
                ],
            );
        }
    };
    
    // Get the instance
    let mut instance = instance_resource.inner.lock().unwrap();
    
    // Build the full method path (e.g., ["component:counter/types", "[method]counter.increment"])
    let mut method_path = interface_path.clone();
    // Resource methods in wasmtime components are exported with special naming:
    // "[method]<resource-type>.<method-name>"
    // We need to determine the resource type name from the resource wrapper
    // For now, we'll use a simplified approach
    // Note: method names use hyphens, not underscores (e.g., "get-value" not "get_value")
    method_path.push(format!("[method]counter.{}", method_name));
    
    // Look up the method function
    let mut lookup_index = None;
    for (index, name) in method_path.iter().enumerate() {
        if let Some(inner) = lookup_index {
            lookup_index = instance
                .get_export(&mut *store, Some(&inner), name.as_str())
                .map(|(_, index)| index);
        } else {
            lookup_index = instance
                .get_export(&mut *store, None, name.as_str())
                .map(|(_, index)| index);
        }
        
        if lookup_index.is_none() {
            let error_msg = format!(
                "Resource method '{}' not found at position {} in path [{}]",
                name,
                index,
                method_path.join(", ")
            );
            let error_tuple = env.error_tuple(error_msg);
            return make_tuple(
                env,
                &[
                    atoms::returned_function_call().encode(env),
                    error_tuple,
                    from,
                ],
            );
        }
    }
    
    let lookup_index = match lookup_index {
        Some(index) => index,
        None => {
            let error_msg = format!(
                "Resource method not found: [{}]",
                method_path.join(", ")
            );
            let error_tuple = env.error_tuple(error_msg);
            return make_tuple(
                env,
                &[
                    atoms::returned_function_call().encode(env),
                    error_tuple,
                    from,
                ],
            );
        }
    };
    
    // Get the function
    let function = match instance.get_func(&mut *store, lookup_index) {
        Some(func) => func,
        None => {
            let error_msg = format!("Could not get function for method '{}'" , method_name);
            let error_tuple = env.error_tuple(error_msg);
            return make_tuple(
                env,
                &[
                    atoms::returned_function_call().encode(env),
                    error_tuple,
                    from,
                ],
            );
        }
    };
    
    // Get the resource from the wrapper
    let resource_any = resource_wrapper.inner.lock().unwrap().clone();
    
    // Prepare arguments: resource is the first argument, followed by method params
    let mut args = vec![Val::Resource(resource_any)];
    
    // Convert the additional parameters
    let param_types: Vec<wasmtime::component::Type> = function
        .params(&*store)
        .into_iter()
        .skip(1) // Skip the resource parameter
        .map(|(_, ty)| ty.clone())
        .collect();
    
    match convert_params(&param_types, params) {
        Ok(mut converted_params) => args.append(&mut converted_params),
        Err(err) => {
            let error_msg = format!("Parameter conversion error: {:?}", err);
            let error_tuple = env.error_tuple(error_msg);
            return make_tuple(
                env,
                &[
                    atoms::returned_function_call().encode(env),
                    error_tuple,
                    from,
                ],
            );
        }
    }
    
    // Allocate space for results
    let result_count = function.results(&*store).len();
    let mut results = vec![Val::Bool(false); result_count];
    
    // Call the method
    let store_id = store.data().store_id;
    match function.call(&mut *store, &args, &mut results) {
        Ok(_) => {
            match function.post_return(&mut *store) {
                Ok(_) => {},
                Err(err) => {
                    let error_msg = format!("post_return error: {:?}", err);
                    let error_tuple = env.error_tuple(error_msg);
                    return make_tuple(
                        env,
                        &[
                            atoms::returned_function_call().encode(env),
                            error_tuple,
                            from,
                        ],
                    );
                }
            }
            
            // Convert results to Elixir terms
            // Convert results to Elixir terms
            let result_terms = vals_to_terms_with_store(results.as_slice(), env, store_id);
            let result = if result_terms.len() == 0 {
                atoms::ok().encode(env)
            } else if result_terms.len() == 1 {
                make_tuple(env, &[atoms::ok().encode(env), result_terms[0]])
            } else {
                let tuple = make_tuple(env, &result_terms);
                make_tuple(env, &[atoms::ok().encode(env), tuple])
            };
            make_tuple(
                env,
                &[
                    atoms::returned_function_call().encode(env),
                    result,
                    from,
                ],
            )
        }
        Err(err) => {
            let error_msg = format!("Method call error: {:?}", err);
            let error_tuple = env.error_tuple(error_msg);
            make_tuple(
                env,
                &[
                    atoms::returned_function_call().encode(env),
                    error_tuple,
                    from,
                ],
            )
        }
    }
}

/// Create a new resource instance (constructor)
// #[rustler::nif(name = "resource_new", schedule = "DirtyCpu")]
pub fn resource_new<'a>(
    env: Env<'a>,
    _store_resource: ResourceArc<ComponentStoreResource>,
    _resource_type_path: Vec<String>,
    _params: Vec<Term<'a>>,
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