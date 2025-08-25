# WASI Preview 2 Implementation Plan

**Last Updated**: 2025-08-25  
**Status**: Phase 1 COMPLETE - Resource method dispatch working!

## Current Status
✅ Core resource infrastructure implemented
✅ Resource wrapping and store tracking working  
✅ Basic WASI P2 runtime linked
✅ **Resource method dispatch WORKING** (Completed 2025-08-25)
🔴 Host-defined resources not implemented

## Implementation Priority

### Phase 1: Critical - Resource Method Dispatch ✅ COMPLETED
**Goal**: Enable calling methods on resources

#### Tasks Completed:
1. ✅ **Fixed resource NIFs** in `native/wasmex/src/resource_methods.rs`
   - ✅ `resource_call_method` - Call methods on existing resources
   - ⏸️ `resource_new` - Constructor calls (deferred - using regular function calls)
   
2. ✅ **Implemented method dispatch logic**
   - ✅ Map method names to wasmtime resource methods
   - ✅ Handle owned vs borrowed semantics
   - ✅ Convert parameters and return values

3. ✅ **Updated exports**
   - ✅ Added NIF to lib/wasmex/native.ex
   - ✅ Proper async scheduling (DirtyCpu)

4. ✅ **Comprehensive tests written**
   - ✅ Test counter increment/get-value/reset methods
   - ✅ Test parameter passing
   - ✅ Test error cases (wrong store protection)

### Phase 2: Important - Resource Lifecycle Management 🚧 NEXT
**Goal**: Prevent memory leaks

#### Tasks:
1. **Automatic cleanup on store destruction**
   - Hook into store Drop implementation
   - Clear resource registry
   - Drop all tracked resources

2. **Resource finalization**
   - Implement Erlang resource destructor
   - Ensure proper cleanup order

3. **Add lifecycle tests**
   - Test resource cleanup on store drop
   - Monitor for memory leaks
   - Test cross-store protection

### Phase 3: WASI Filesystem Resources
**Goal**: Full filesystem support via resources

#### Tasks:
1. **Create filesystem test component**
   - Open/read/write file operations
   - Directory operations
   - File metadata access

2. **Test resource-based file handles**
   - Position tracking
   - Concurrent access
   - Error handling

3. **Integration tests**
   - Read/write real files
   - Directory traversal
   - Permission handling

### Phase 4: WASI Network Resources  
**Goal**: Socket and network stream support

#### Tasks:
1. **TCP socket component tests**
   - Create socket resources
   - Connect/bind operations
   - Stream read/write

2. **UDP socket tests**
   - Datagram operations
   - Multicast support

3. **HTTP client resources**
   - Request/response resources
   - Stream body handling

### Phase 5: Host-Defined Resources
**Goal**: Allow Elixir to define resources

#### Tasks:
1. **Design host resource API**
   - Resource trait definition
   - Method dispatch from WASM
   - State management

2. **Implement host resource wrapper**
   - Elixir callback mechanism
   - Type conversion
   - Error propagation

3. **Example implementations**
   - Database connection resource
   - Message queue resource
   - Custom stateful resources

## Test Strategy

### Unit Tests
- Each NIF function tested independently
- Resource lifecycle tests
- Type conversion tests
- Error case coverage

### Integration Tests  
- Real WASI components
- Multi-resource scenarios
- Cross-component resource sharing
- Performance benchmarks

### Component Test Matrix
| Component | Purpose | Priority |
|-----------|---------|----------|
| counter | Basic resource methods | ✅ Done |
| filesystem | File/Dir resources | High |
| network | Socket resources | High |
| streams | I/O stream resources | Medium |
| clock | Timer resources | Low |
| random | RNG resources | Low |

## Success Criteria

1. **Phase 1 Complete**: ✅ Can call methods on counter resource (DONE!)
2. **Phase 2 Complete**: No memory leaks in 1000x create/destroy cycles
3. **Phase 3 Complete**: Can read/write files via resources
4. **Phase 4 Complete**: Can establish TCP connections
5. **Phase 5 Complete**: Can define custom Elixir resources

## Implementation Notes

### Key Files to Modify
- `native/wasmex/src/resource_methods.rs` - Main implementation
- `native/wasmex/src/lib.rs` - NIF exports
- `native/wasmex/src/wasi_resource.rs` - Resource wrapper enhancements
- `native/wasmex/src/component_instance.rs` - Instance method lookups
- `lib/wasmex/components/resource.ex` - Elixir API

### Testing Commands
```bash
# Run resource tests
mix test test/component_resource_test.exs

# Run with verbose output  
mix test test/component_resource_test.exs --trace

# Run specific test
mix test test/component_resource_test.exs:LINE_NUMBER

# Check for memory leaks
valgrind --leak-check=full mix test

# Build test components
cd test/component_fixtures/counter-component && cargo component build --release
```

### Debugging Tips
1. Set RUST_BACKTRACE=1 for panic traces
2. Use dbg!() macros in Rust for quick debugging
3. Check wasmtime ResourceAny documentation
4. Monitor STORE_ID_COUNTER for store leaks
5. Use `wasm-tools component wit` to verify interfaces

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking existing functionality | Comprehensive test suite before changes |
| Memory leaks | Valgrind testing, resource tracking |
| Performance regression | Benchmark before/after |
| API incompatibility | Maintain backward compatibility |
| Security issues | Store isolation validation |

## Timeline Estimate
- Phase 1: ✅ COMPLETED (took ~3 hours)
- Phase 2: 1-2 hours  
- Phase 3: 2-3 hours
- Phase 4: 2-3 hours
- Phase 5: 3-4 hours

Remaining: ~10 hours of implementation + testing