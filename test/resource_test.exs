defmodule Wasmex.ResourceTest do
  use ExUnit.Case
  doctest Wasmex.Components.Resource
  
  alias Wasmex.Components.Resource
  
  describe "resource module" do
    test "creates resource struct with correct fields" do
      resource = Resource.__wrap_resource__(
        <<1, 2, 3>>,
        :owned,
        "test-resource",
        make_ref()
      )
      
      assert %Resource{} = resource
      assert resource.type == :owned
      assert resource.type_name == "test-resource"
      assert resource.resource == <<1, 2, 3>>
    end
    
    test "owned? returns true for owned resources" do
      resource = %Resource{type: :owned}
      assert Resource.owned?(resource)
      refute Resource.borrowed?(resource)
    end
    
    test "borrowed? returns true for borrowed resources" do
      resource = %Resource{type: :borrowed}
      assert Resource.borrowed?(resource)
      refute Resource.owned?(resource)
    end
    
    test "type_name returns the resource type name" do
      resource = %Resource{type_name: "file-handle"}
      assert Resource.type_name(resource) == "file-handle"
    end
    
    test "drop returns error for borrowed resources" do
      resource = %Resource{type: :borrowed}
      assert {:error, "Cannot drop a borrowed resource"} = Resource.drop(resource)
    end
  end
  
  # Integration tests with actual WASI components would go here
  # These would require:
  # 1. A test component with resource types
  # 2. Store and component instance setup
  # 3. Actual resource creation and manipulation
  
  describe "WASI resource integration" do
    @describetag :skip
    
    setup do
      # This would set up a store and load a test component
      # with resource types
      :ok
    end
    
    test "can create and drop an owned resource" do
      # Test creating a resource from a component function
      # and then dropping it
    end
    
    test "can pass borrowed resources to functions" do
      # Test passing a borrowed resource to a component function
    end
    
    test "resource registry tracks active resources" do
      # Test that the resource registry properly tracks resources
    end
  end
end