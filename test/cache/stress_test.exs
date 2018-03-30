defmodule GenSpoxy.Cache.StressTests do
  use ExUnit.Case, async: false

  alias GenSpoxy.Stores.Ets

  import Macros.Tests

  defquery(
    Stress.SampleQuery,
    do_req: fn req ->
      :timer.sleep(200)
      {:ok, "response for #{inspect(req)}"}
    end
  )

  defmodule Stress.SampleCache do
    use GenSpoxy.Cache, query_module: Stress.SampleQuery
  end

  setup_all do
    Stress.SampleQuery.Supervisor.start_link()
    :ok
  end

  setup do
    Ets.reset_all!()
    :ok
  end

  test "multiple concurrent clients calling the same request" do
    n = 1000

    table_name = "table-query-cache-stress-1"
    req = ["req-query-cache-stress-1", "newest"]
    ttl_ms = 100

    assert {:miss, _reason} = Stress.SampleCache.get(req, table_name: table_name)

    opts = [table_name: table_name, do_janitor_work: false, blocking: true, ttl_ms: ttl_ms]

    active_task = Stress.SampleCache.async_get_or_fetch(req, opts)

    passive_tasks =
      Enum.map(2..n, fn _ ->
        Stress.SampleCache.async_get_or_fetch(req, opts)
      end)

    Enum.each(passive_tasks, fn task ->
      {:ok, "response for [\"req-query-cache-stress-1\", \"newest\"]", _bench} =
        Stress.SampleCache.await(task)
    end)

    {:ok, "response for [\"req-query-cache-stress-1\", \"newest\"]", _bench} =
      Stress.SampleCache.await(active_task)
  end
end
