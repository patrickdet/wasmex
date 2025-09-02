# Clean Resource API Example
# No more async callbacks, from parameters, or receive blocks!

# Setup
{:ok, store} = Wasmex.Components.Store.new()
{:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
{:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})

# Create resources - simple and clean
{:ok, counter1} = Wasmex.Components.Instance.new_resource(
  instance,
  ["component:counter/types", "counter"],
  [10]  # initial value
)

{:ok, counter2} = Wasmex.Components.Instance.new_resource(
  instance,
  ["component:counter/types", "counter"],
  [20]  # initial value
)

# Call methods - no boilerplate!
{:ok, value1} = Wasmex.Components.Instance.call(instance, counter1, "get-value")
# Returns 10

{:ok, value2} = Wasmex.Components.Instance.call(instance, counter2, "get-value")
# Returns 20

# Increment counter1
{:ok, new_value} = Wasmex.Components.Instance.call(instance, counter1, "increment")
# Returns 11

# Reset counter2 with a parameter
:ok = Wasmex.Components.Instance.call(instance, counter2, "reset", [100])

# Verify the changes
{:ok, value1} = Wasmex.Components.Instance.call(instance, counter1, "get-value")
# Returns 11

{:ok, value2} = Wasmex.Components.Instance.call(instance, counter2, "get-value")
# Returns 100

# That's it! Clean, simple, synchronous.
# No async callbacks, no from parameters, no receive blocks.
# Just straightforward function calls that return results.