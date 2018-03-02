defmodule GenSpoxy.Cache.Tests do
  use ExUnit.Case

  alias GenSpoxy.Stores.Ets

  import GenSpoxy.Prerender.Macros

  defprerender(SamplePrerender, do_req: fn req -> {:ok, "response for #{inspect(req)}"} end)

  defmodule SampleCache do
    use GenSpoxy.Cache, prerender_module: SamplePrerender
  end

  setup_all do
    Ets.Supervisor.start_link()
    SamplePrerender.Supervisor.start_link()
    :ok
  end

  setup do
    Ets.reset_all!()
    :ok
  end

  test "cache miss triggers prerender-fetch and stores the response" do
    table_name = "table-prerender-cache-test-1"
    req = ["req-cache-test-1", "newest"]
    ttl_ms = 200

    result = SampleCache.get(req, table_name: table_name)
    assert {:miss, _reason} = result

    resp =
      SampleCache.get_or_fetch(
        req,
        table_name: table_name,
        do_janitor_work: false,
        blocking: true,
        ttl_ms: ttl_ms
      )

    assert {:ok, "response for [\"req-cache-test-1\", \"newest\"]"} = resp

    resp = SampleCache.get(req, table_name: table_name)
    assert {:hit, {"response for [\"req-cache-test-1\", \"newest\"]", %{}}} = resp

    resp =
      SampleCache.get_or_fetch(
        req,
        table_name: table_name,
        do_janitor_work: false,
        blocking: true,
        ttl_ms: ttl_ms
      )

    assert {:ok, "response for [\"req-cache-test-1\", \"newest\"]"} = resp

    # invalidate
    req_key = SamplePrerender.calc_req_key(req)
    Ets.invalidate!(table_name, req_key)
    assert {:miss, _reason} = SampleCache.get(req, table_name: table_name)
  end

  test "stale data invalidates the request when `blocking=true`" do
    table_name = "table-prerender-cache-test-2"
    req = ["req-cache-test-2", "newest"]
    ttl_ms = 200

    assert {:miss, _reason} = SampleCache.get(req, table_name: table_name)

    # triggers fetch-and-store
    SampleCache.get_or_fetch(
      req,
      table_name: table_name,
      do_janitor_work: false,
      blocking: true,
      ttl_ms: ttl_ms
    )

    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit,
            {"response for [\"req-cache-test-2\", \"newest\"]", %{version: version} = metadata}} =
             resp

    # data is still fresh
    refute SampleCache.should_invalidate?(req, resp, metadata)

    # waiting `ttl_ms * 3` ms so that the data will become stale for sure
    :timer.sleep(ttl_ms * 3)

    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit,
            {"response for [\"req-cache-test-2\", \"newest\"]", %{version: ^version} = metadata}} =
             resp

    # data should have become stale by now
    assert SampleCache.should_invalidate?(req, resp, metadata)

    # this fetch-and-store should trigger a refresh to the stale data
    resp =
      SampleCache.get_or_fetch(
        req,
        table_name: table_name,
        do_janitor_work: false,
        blocking: true,
        ttl_ms: ttl_ms
      )

    assert {:ok, "response for [\"req-cache-test-2\", \"newest\"]"} = resp

    # asserting the stored metadata has been changed
    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit, {"response for [\"req-cache-test-2\", \"newest\"]", %{version: new_version}}} =
             resp

    refute version == new_version
  end

  test "returns stale data and refreshes the cache in the background when `blocking=false` (which is the default setting)" do
    table_name = "table-prerender-cache-test-3"
    req = ["req-cache-test-3", "newest"]
    ttl_ms = 200

    assert {:miss, _reason} = SampleCache.get(req, table_name: table_name)

    # triggers fetch-and-store
    SampleCache.get_or_fetch(
      req,
      table_name: table_name,
      do_janitor_work: false,
      blocking: true,
      ttl_ms: ttl_ms
    )

    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit,
            {"response for [\"req-cache-test-3\", \"newest\"]", %{version: version} = metadata}} =
             resp

    # data is still fresh
    refute SampleCache.should_invalidate?(req, resp, metadata)

    # waiting `ttl_ms * 3` ms so that the data will become stale for sure
    :timer.sleep(ttl_ms * 3)

    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit,
            {"response for [\"req-cache-test-3\", \"newest\"]", %{version: ^version} = metadata}} =
             resp

    # data should have become stale by now
    assert SampleCache.should_invalidate?(req, resp, metadata)

    # this fetch-and-store should trigger a refresh in the background
    resp =
      SampleCache.get_or_fetch(
        req,
        table_name: table_name,
        do_janitor_work: false,
        background: false,
        ttl_ms: ttl_ms
      )

    assert {:ok, "response for [\"req-cache-test-3\", \"newest\"]"} = resp

    # asserting the stored metadata has been changed
    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit, {"response for [\"req-cache-test-3\", \"newest\"]", %{version: new_version}}} =
             resp

    assert version == new_version
  end

  test "cache auto-invalidates expired data via a background janitor work" do
    table_name = "table-prerender-cache-test-4"
    req = ["req-cache-test-4", "newest"]
    ttl_ms = 200

    assert {:miss, _reason} = SampleCache.get(req, table_name: table_name)

    # triggers fetch-and-store
    SampleCache.get_or_fetch(
      req,
      table_name: table_name,
      do_janitor_work: true,
      blocking: true,
      ttl_ms: ttl_ms
    )

    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit,
            {"response for [\"req-cache-test-4\", \"newest\"]", %{version: _version} = metadata}} =
             resp

    # data is still fresh
    refute SampleCache.should_invalidate?(req, resp, metadata)

    :timer.sleep(ttl_ms * 3)

    resp = SampleCache.get(req, table_name: table_name)
    assert {:miss, _reason} = resp
  end

  test "cache skips janitor work when `do_janitor_work=false`" do
    table_name = "table-prerender-cache-test-5"
    req = ["req-cache-test-5", "newest"]
    ttl_ms = 200

    assert {:miss, _reason} = SampleCache.get(req, table_name: table_name)

    # triggers fetch-and-store
    SampleCache.get_or_fetch(
      req,
      table_name: table_name,
      do_janitor_work: false,
      blocking: true,
      ttl_ms: ttl_ms
    )

    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit,
            {"response for [\"req-cache-test-5\", \"newest\"]", %{version: _version} = metadata}} =
             resp

    # data is still fresh
    refute SampleCache.should_invalidate?(req, resp, metadata)

    # waiting `ttl_ms * 3` ms so that the data will become stale for sure
    :timer.sleep(ttl_ms * 3)

    resp = SampleCache.get(req, table_name: table_name)

    assert {:hit,
            {"response for [\"req-cache-test-5\", \"newest\"]", %{version: _version} = metadata}} =
             resp

    # data is stale
    assert SampleCache.should_invalidate?(req, resp, metadata)
  end
end
