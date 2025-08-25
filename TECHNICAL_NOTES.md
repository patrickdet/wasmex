# Technical Notes: WASI Resource Implementation

## Quick Reference

### Critical Files to Know
```
native/wasmex/src/
├── wasi_resource.rs         # Core: WasiResourceWrapper struct
├── resource_registry.rs     # Tracking: Per-store resource management
├── resource_methods.rs      # Stubs: Method dispatch (TODO)
├── component_type_conversion.rs  # Modified: Val::Resource handling
└── store.rs                 # Modified: Added resource_registry + store_id

lib/wasmex/components/
└── resource.ex              # Elixir API for resources

test/
├── component_resource_test.exs  # Resource tests (4 passing)
└── component_fixtures/
    └── counter-component/   # Working test component with resources
```

### Key Code Patterns

#### Creating a Resource (Rust side)
```rust
// When component returns a resource:
Val::Resource(resource_any) => {
    let wrapper = WasiResourceWrapper::new(resource_any, store_id);
    Ok(ResourceArc::new(wrapper))
}
```

#### Using a Resource (Elixir side)
```elixir
# Call function that returns resource
{:ok, resource} = Instance.call_function(instance, 
  ["component:counter/types", "make-counter"], [5], from)

# resource is now #Reference<...>

# Pass it back to component
{:ok, result} = Instance.call_function(instance,
  ["component:counter/types", "use-counter"], [resource], from)
```

### Type Signatures

#### Resource Types in WIT
```wit
own<T>     # Owned resource - caller must drop
borrow<T>  # Borrowed resource - temporary use
```

#### Wasmtime Types
```rust
wasmtime::component::ResourceAny  # Type-erased resource
wasmtime::component::Val::Resource(ResourceAny)  # In Val enum
wasmtime::component::Type::Own(ResourceType)     # Owned type
wasmtime::component::Type::Borrow(ResourceType)  # Borrowed type
```

### Known Issues & Solutions

#### Issue: "Function not found" errors
**Solution**: Resource methods are stubs. The NIFs are commented out in resource_methods.rs

#### Issue: Cross-store resource usage
**Solution**: Each resource tracks its store_id, validated on use

#### Issue: Resource leaks
**Solution**: Explicit drop via Resource.drop/1 in Elixir

### Testing Gotchas

1. **Async Calls**: Component functions are async, results come as messages:
```elixir
:ok = Instance.call_function(instance, func, args, from)
receive do
  {:returned_function_call, {:ok, result}, ^from} -> result
end
```

2. **Function Paths**: Use full namespace for exports:
```elixir
# Wrong: ["types", "make-counter"]
# Right: ["component:counter/types", "make-counter"]
```

3. **Component Building**: Must use cargo-component:
```bash
cargo component build --release  # Regular cargo build won't work!
```

### Debugging Tips

1. **Check WIT exports**:
```bash
wasm-tools component wit path/to/component.wasm
```

2. **Trace resource creation**:
Look for `Val::Resource` in component_type_conversion.rs

3. **Store ID tracking**:
Check `STORE_ID_COUNTER` in store.rs for unique IDs

4. **Resource wrapping**:
Set breakpoint in `WasiResourceWrapper::new()`

### Performance Considerations

- Each resource has a Mutex (potential contention)
- ResourceRegistry uses HashMap with Mutex
- Store IDs are atomically incremented
- No automatic cleanup yet (manual drop required)

### Security Notes

- Resources CANNOT cross store boundaries (enforced)
- Borrowed resources cannot be dropped by borrower
- Store isolation prevents resource sharing between instances
- Resource types are validated at runtime (not compile time)

### Future Implementation Tasks

1. **resource_methods.rs**: Implement actual method dispatch
2. **Host resources**: Add callback mechanism for Elixir-defined resources
3. **Auto-cleanup**: Integrate registry with store destruction
4. **Resource properties**: Support for resource fields/properties
5. **Better errors**: Improve error messages for resource type mismatches

### Common Commands

```bash
# Rebuild everything
mix compile --force

# Just rebuild Rust
cd native/wasmex && cargo build --release

# Run specific test
mix test test/component_resource_test.exs:47

# Check component interface
wasm-tools component wit <component.wasm>

# See what's exported
wasm-tools component exports <component.wasm>
```

### Git Status
- Branch: `wasi-resources`
- Last commit: `4ec3174 feat: Add WASI component resource support`
- All changes committed
- Ready to push or continue development