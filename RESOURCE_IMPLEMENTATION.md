# WASI Component Resources Implementation Plan

## Overview
This document outlines the implementation plan for adding WASI component resource support to wasmex. Resources are handles to entities that exist outside of the component (files, sockets, HTTP connections, etc.) and are fundamental for WASI interfaces.

## Current State Analysis
- Wasmex has comprehensive component model support but lacks resource handling
- Type conversion (`component_type_conversion.rs`) covers all types except resources  
- Wasmtime's `Val` enum includes `Resource(ResourceAny)` variant
- Resources use owned (`own<T>`) and borrowed (`borrow<T>`) handle semantics

## Implementation Plan

### Phase 1: Basic Resource Support (Current)

#### 1.1 Core Resource Infrastructure

**Rust-Side Resource Wrapper** (`native/wasmex/src/wasi_resource.rs`):
```rust
pub struct WasiResourceWrapper {
    inner: Mutex<ResourceAny>,
    resource_type: ResourceType,
    is_owned: bool,
    store_id: usize, // Link to the store that owns this resource
}

pub enum ResourceType {
    GuestDefined { type_name: String },
    HostDefined { type_name: String },
}
```

**Resource Registry** (`native/wasmex/src/resource_registry.rs`):
- Track active resources per store
- Prevent cross-store resource usage
- Handle cleanup on store destruction

#### 1.2 Type Conversion Extensions

Extend `component_type_conversion.rs` to handle:
- `Type::Own(resource_type)` → Elixir resource reference
- `Type::Borrow(resource_type)` → Elixir resource reference
- `Val::Resource(ResourceAny)` ↔ Elixir term conversion

#### 1.3 Elixir-Side Resource Module

```elixir
defmodule Wasmex.Components.Resource do
  @type t :: %__MODULE__{
    resource: binary(),
    type: :owned | :borrowed,
    type_name: String.t(),
    store_ref: reference()
  }
  
  def drop(resource)
end
```

### Phase 2: Method Dispatch (Week 2-3)

#### 2.1 Resource Method Calls
- Implement method dispatch for guest-defined resources
- Support resource constructors, methods, and static functions

#### 2.2 Host-Defined Resources
- Allow Elixir to define host resources
- Implement callback mechanism for host resource methods

### Phase 3: Advanced Features (Week 4-5)

#### 3.1 Lifecycle Management
- Automatic cleanup using Elixir process monitoring
- Reference counting coordination between Rust and Erlang

#### 3.2 Import/Export Support
- Functions returning resources (e.g., `open-file`)
- Functions accepting resources as parameters
- Ownership transfer semantics

### Phase 4: WASI Integration (Week 6)

#### 4.1 Real WASI Resources
- Test with WASI filesystem operations
- HTTP resource support
- Socket resource support

## File Structure

```
native/wasmex/src/
├── wasi_resource.rs        # Resource wrapper and types
├── resource_registry.rs    # Resource tracking and management
└── component_type_conversion.rs # Extended with resource support

lib/wasmex/components/
├── resource.ex             # Elixir resource module
└── resource_manager.ex     # Lifecycle management

test/
├── resource_test.exs       # Resource-specific tests
└── fixtures/
    └── resource_test/      # Test components with resources
```

## Safety Considerations

1. **Ownership Validation**
   - Prevent double-drop of owned resources
   - Ensure borrowed resources aren't dropped by borrower
   - Runtime type checking for resource operations

2. **Store Isolation**
   - Resources bound to originating store
   - Cross-store usage triggers errors

3. **Deadlock Prevention**
   - Careful mutex ordering
   - Timeout mechanisms for resource operations

## Testing Strategy

### Unit Tests
- Resource creation and destruction
- Ownership transfer semantics
- Type conversion edge cases

### Integration Tests
```wit
interface test-resources {
  resource counter {
    constructor(initial: u32);
    increment: func() -> u32;
    get-value: func() -> u32;
  }
  
  use-counter: func(c: borrow<counter>) -> u32;
  transfer-counter: func(c: own<counter>);
}
```

### WASI Tests
```elixir
test "file resource operations" do
  {:ok, file_resource} = call_function("open-file", ["test.txt"])
  assert %Resource{type: :owned} = file_resource
  
  {:ok, content} = call_function("read-file", [file_resource, 100])
  Resource.drop(file_resource)
end
```

## Success Metrics

- All wasmtime `Val::Resource` operations supported
- WASI filesystem operations work correctly
- No resource leaks under stress testing
- Clear error messages for resource misuse
- Compatible with existing wasmex API patterns

## Known Challenges

1. **Reference Counting**: Coordinating Rust Arc with Erlang reference counting
2. **Process Boundaries**: Resources crossing Erlang process boundaries  
3. **Type Safety**: Runtime type checking for resource operations
4. **Performance**: Mutex contention in high-throughput scenarios
5. **Debugging**: Tracing resource lifecycle across language boundaries

## Current Implementation Status

- [x] Documentation and planning
- [ ] Basic resource wrapper structure
- [ ] Type conversion for resources
- [ ] Elixir resource module
- [ ] Resource drop functionality
- [ ] Basic tests
- [ ] Method dispatch
- [ ] Host-defined resources
- [ ] WASI integration