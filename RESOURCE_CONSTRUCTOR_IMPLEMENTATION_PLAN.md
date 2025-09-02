# Resource Constructor Implementation Plan

## Overview
Implement the `resource_new` function to enable direct instantiation of WASM component resources via their constructors from Elixir, completing the resource management functionality for the wasmex library.

## Current State Analysis

### What Works Now
1. **Resource Methods**: Can call methods on existing resources via `resource_call_method`
2. **Factory Functions**: Can create resources using regular exported functions (e.g., `make-counter`)
3. **Resource Wrapping**: `WasiResourceWrapper` properly wraps and manages resource lifecycles
4. **Host Resources**: Host-defined resources work via `ResourceBehaviour`/`ResourceServer`

### What's Missing
- Direct constructor invocation for WASM component resources
- The `resource_new` function in `native/wasmex/src/resource_methods.rs` is stubbed out

### Current Workaround
Tests use factory functions instead of constructors:
```elixir
# Current workaround - using factory function
Wasmex.Components.Instance.call_function(
  instance,
  ["component:counter/types", "make-counter"],
  [5],
  from
)

# Desired - using constructor directly
Wasmex.Components.Instance.resource_new(
  instance,
  ["component:counter/types", "counter"],
  [5],
  from
)
```

## Technical Requirements

### Component Model Constructor Naming
In the WASM component model, constructors follow specific naming patterns:
- Constructor export: `"[constructor]<resource-name>"`
- Method export: `"[method]<resource-name>.<method-name>"`
- Static method export: `"[static]<resource-name>.<method-name>"`

### Example WIT Definition
```wit
package component:counter;

interface types {
    resource counter {
        constructor(initial: u32);    // Exported as "[constructor]counter"
        increment: func() -> u32;      // Exported as "[method]counter.increment"
        get-value: func() -> u32;      // Exported as "[method]counter.get-value"
    }
}
```

### Wasmtime API Requirements
1. **Type Resolution**: Need to resolve the resource type from the component
2. **Constructor Lookup**: Find the constructor function in exports
3. **Type Signature**: Get parameter and return types for validation
4. **Instance Creation**: Call constructor and get `ResourceAny`
5. **Store Management**: Register resource with the store

## Detailed Implementation Plan

### Phase 1: Type Resolution and Discovery

#### 1.1 Resource Type Lookup
```rust
// In resource_methods.rs
fn find_resource_type(
    instance: &ComponentInstance,
    store: &mut Store<ComponentStoreData>,
    type_path: Vec<String>,
) -> Result<wasmtime::component::ResourceType, String> {
    // Navigate through the component exports to find the resource type
    // Path like: ["component:counter/types", "counter"]
    // 1. Get the interface (component:counter/types)
    // 2. Find the resource type definition (counter)
    // 3. Return the ResourceType for constructor lookup
}
```

#### 1.2 Constructor Function Discovery
```rust
fn find_constructor(
    instance: &ComponentInstance,
    store: &mut Store<ComponentStoreData>,
    resource_name: &str,
) -> Result<(Func, Vec<Type>), String> {
    // Build constructor name: "[constructor]<resource-name>"
    let constructor_name = format!("[constructor]{}", resource_name);
    
    // Look up the constructor in the component's exports
    // Return both the Func and its parameter types
}
```

### Phase 2: Constructor Invocation

#### 2.1 Update `resource_new` Function Structure
```rust
pub fn resource_new<'a>(
    env: Env<'a>,
    store_resource: ResourceArc<ComponentStoreResource>,
    instance_resource: ResourceArc<ComponentInstanceResource>,
    resource_type_path: Vec<String>,
    params: Vec<Term<'a>>,
    from: Term<'a>,
) -> Term<'a> {
    // Spawn thread for async execution (like resource_call_method)
    let pid = env.pid();
    let mut thread_env = OwnedEnv::new();
    let saved_params = thread_env.save(params);
    let saved_from = thread_env.save(from);
    
    thread::spawn(move || {
        thread_env.send_and_clear(&pid, |thread_env| {
            execute_resource_constructor(
                thread_env,
                store_resource,
                instance_resource,
                resource_type_path,
                saved_params,
                saved_from,
            )
        })
    });
    
    atoms::ok().encode(env)
}
```

#### 2.2 Implement Constructor Execution
```rust
fn execute_resource_constructor(
    env: Env,
    store_resource: ResourceArc<ComponentStoreResource>,
    instance_resource: ResourceArc<ComponentInstanceResource>,
    resource_type_path: Vec<String>,
    saved_params: SavedTerm,
    saved_from: SavedTerm,
) -> Term {
    // 1. Lock store and instance
    let mut store = store_resource.inner.lock().unwrap();
    let instance = instance_resource.inner.lock().unwrap();
    
    // 2. Parse the resource type path
    // Split into interface path and resource name
    // e.g., ["component:counter/types", "counter"]
    let (interface_path, resource_name) = parse_resource_path(resource_type_path);
    
    // 3. Find the constructor function
    let constructor_name = format!("[constructor]{}", resource_name);
    let func = lookup_constructor(&instance, &mut *store, &interface_path, &constructor_name)?;
    
    // 4. Convert parameters
    let param_types = func.params(&*store);
    let wasm_params = convert_params(&param_types, params)?;
    
    // 5. Call the constructor
    let mut results = vec![Val::Bool(false); 1]; // Constructors return 1 resource
    func.call(&mut *store, &wasm_params, &mut results)?;
    func.post_return(&mut *store)?;
    
    // 6. Extract the resource from results
    let resource_any = match &results[0] {
        Val::Resource(r) => r.clone(),
        _ => return error_response("Constructor did not return a resource"),
    };
    
    // 7. Create WasiResourceWrapper
    let wrapper = WasiResourceWrapper::new(resource_any, store.data().store_id);
    let resource_arc = ResourceArc::new(wrapper);
    
    // 8. Register with store's resource registry
    store.data().resource_registry.register_resource(
        resource_arc.clone(),
        resource_name.to_string()
    );
    
    // 9. Return success with resource handle
    make_tuple(
        env,
        &[
            atoms::returned_function_call().encode(env),
            make_tuple(env, &[atoms::ok().encode(env), resource_arc.encode(env)]),
            from,
        ],
    )
}
```

### Phase 3: Integration Points

#### 3.1 Update Native Module
```elixir
# lib/wasmex/native.ex
def resource_new(_store, _instance, _type_path, _params, _from), do: error()
```
Change to properly declare the NIF.

#### 3.2 Update Elixir Wrapper
```elixir
# lib/wasmex/components/component_instance.ex
def resource_new(instance, resource_type_path, params, from) do
  %__MODULE__{resource: instance_resource, store_resource: store_resource} = instance
  
  Wasmex.Native.resource_new(
    store_resource,
    instance_resource,
    resource_type_path,
    params,
    from
  )
end
```

### Phase 4: Path Resolution Strategy

#### 4.1 Handle Different Path Formats
```rust
fn parse_resource_path(path: Vec<String>) -> Result<(Vec<String>, String), String> {
    // Handle different formats:
    // 1. ["component:counter/types", "counter"] - interface + resource
    // 2. ["counter"] - just resource name (use default interface)
    // 3. ["wasi:http/types", "incoming-request"] - WASI resource
    
    if path.is_empty() {
        return Err("Empty resource path".to_string());
    }
    
    if path.len() == 1 {
        // Just resource name, no interface specified
        Ok((vec![], path[0].clone()))
    } else {
        // Interface path + resource name
        let resource_name = path.last().unwrap().clone();
        let interface_path = path[0..path.len()-1].to_vec();
        Ok((interface_path, resource_name))
    }
}
```

#### 4.2 Export Lookup with Nesting
```rust
fn lookup_constructor(
    instance: &ComponentInstance,
    store: &mut Store<ComponentStoreData>,
    interface_path: &[String],
    constructor_name: &str,
) -> Result<Func, String> {
    // Navigate nested exports
    let mut current_index = None;
    
    // First navigate to the interface
    for segment in interface_path {
        current_index = if let Some(index) = current_index {
            instance.get_export(store, Some(&index), segment)
                .map(|(_, idx)| idx)
        } else {
            instance.get_export(store, None, segment)
                .map(|(_, idx)| idx)
        };
        
        if current_index.is_none() {
            return Err(format!("Interface segment '{}' not found", segment));
        }
    }
    
    // Now look for the constructor
    let (export, index) = instance.get_export(
        store,
        current_index.as_ref(),
        constructor_name
    ).ok_or_else(|| format!("Constructor '{}' not found", constructor_name))?;
    
    // Verify it's a function
    instance.get_func(store, index)
        .ok_or_else(|| format!("Export '{}' is not a function", constructor_name))
}
```

## Testing Strategy

### 1. Unit Tests (Rust)
```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_parse_resource_path() {
        // Test various path formats
    }
    
    #[test]
    fn test_constructor_name_generation() {
        // Verify correct constructor naming
    }
}
```

### 2. Integration Tests (Elixir)

#### 2.1 Modify Existing Tests
Update `test/components/resource_test.exs` to use constructors:
```elixir
test "can create counter using constructor" do
  {:ok, store} = Wasmex.Components.Store.new()
  {:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
  {:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})
  
  from = self()
  
  # Use constructor instead of factory function
  :ok = Wasmex.Components.Instance.resource_new(
    instance,
    ["component:counter/types", "counter"],
    [42],  # initial value
    from
  )
  
  receive do
    {:returned_function_call, {:ok, counter}, ^from} ->
      assert is_reference(counter)
      # Test method calls on the resource...
  end
end
```

#### 2.2 Add New Test Cases
```elixir
describe "resource constructors" do
  test "constructor with no parameters"
  test "constructor with multiple parameters"
  test "constructor with complex types"
  test "constructor failure handling"
  test "invalid resource type path"
end
```

### 3. Test Components
Ensure test components have proper constructors:
- `test/component_fixtures/counter-component/src/lib.rs`
- `test/component_fixtures/network-component/src/lib.rs`
- `test/component_fixtures/filesystem-component/src/lib.rs`

## Error Handling

### Expected Error Cases
1. **Invalid Path**: Resource type doesn't exist
2. **No Constructor**: Resource has no constructor defined
3. **Parameter Mismatch**: Wrong types or count
4. **Store Mismatch**: Resource/store ownership issues
5. **Memory Limits**: Constructor exceeds memory limits

### Error Response Format
```rust
fn error_response(env: Env, msg: String, from: Term) -> Term {
    make_tuple(
        env,
        &[
            atoms::returned_function_call().encode(env),
            make_tuple(env, &[atoms::error().encode(env), msg.encode(env)]),
            from,
        ],
    )
}
```

## Potential Challenges

### 1. Type System Complexity
- WASM component model has complex type system
- Need to handle all parameter types correctly
- Resource types may be nested in interfaces

### 2. Async Pattern Consistency
- Must match existing async pattern used in `resource_call_method`
- Thread spawning and message passing to Elixir process

### 3. Resource Registry Management
- Ensure proper registration in store's resource registry
- Handle cleanup on failure
- Prevent resource leaks

### 4. WASI Resources
- Some resources might be WASI-provided (e.g., sockets, files)
- May need special handling for system resources

## Implementation Order

1. **Start Simple**: Basic constructor with primitive parameters
2. **Add Complexity**: Handle complex types (records, variants, lists)
3. **Error Cases**: Comprehensive error handling
4. **Performance**: Optimize lookup and caching
5. **Documentation**: Update docs and examples

## Success Criteria

1. ✅ All existing tests pass
2. ✅ Constructor-based tests replace factory function tests
3. ✅ No memory leaks in resource creation
4. ✅ Proper error messages for all failure cases
5. ✅ Documentation updated with constructor examples
6. ✅ Performance comparable to factory functions

## Code Locations

### Files to Modify
- `native/wasmex/src/resource_methods.rs` - Main implementation
- `native/wasmex/src/component_instance.rs` - May need export helpers
- `native/wasmex/src/atoms.rs` - May need new atoms
- `lib/wasmex/native.ex` - NIF declaration
- `lib/wasmex/components/component_instance.ex` - Elixir wrapper

### Files to Test
- `test/components/resource_test.exs` - Main test file
- `test/components/network_resource_test.exs` - Network resources
- All component fixtures in `test/component_fixtures/`

## Timeline Estimate

- **Phase 1**: Type Resolution - 2-3 hours
- **Phase 2**: Constructor Implementation - 3-4 hours  
- **Phase 3**: Integration - 1-2 hours
- **Phase 4**: Path Resolution - 2-3 hours
- **Testing**: 2-3 hours
- **Documentation**: 1 hour

**Total**: ~12-16 hours of focused work

## Next Steps

1. Start with the simplest case: counter constructor
2. Get basic flow working end-to-end
3. Add type complexity incrementally
4. Ensure all tests pass at each step
5. Profile for performance issues
6. Document the new functionality