defmodule Spoxy.Stores.Ets.Tests do
  use ExUnit.Case, async: true

  alias GenSpoxy.Stores.Ets

  setup_all do
    Ets.Supervisor.start_link()
    Ets.reset_all!()

    :ok
  end

  test "returns 'nil' when data isn't in the cache" do
    lookup = Ets.lookup_req("req-ets-test-1", "key-1")

    assert is_nil(lookup)
  end

  test "returns cached data if exists" do
    table_name = "table-ets-test-2"

    Ets.store_req!(
      table_name,
      ["req-ets-test-2", "newest"],
      "key-2",
      "resp for req",
      %{etag: 10},
      ttl_ms: 10
    )

    lookup = Ets.lookup_req(table_name, "key-2")
    assert {"resp for req", %{etag: 10, uuid: _uuid}} = lookup
  end

  test "data invalidation" do
    table_name = "table-ets-test-3"

    Ets.store_req!(
      table_name,
      ["req-ets-test-3", "newest"],
      "key-3",
      "resp for req",
      %{etag: 10},
      ttl_ms: 10
    )

    lookup = Ets.lookup_req(table_name, "key-3")
    assert {"resp for req", %{etag: 10, uuid: _uuid}} = lookup

    Ets.invalidate!(table_name, "key-3")

    lookup = Ets.lookup_req(table_name, "key-3")
    assert is_nil(lookup)
  end
end
