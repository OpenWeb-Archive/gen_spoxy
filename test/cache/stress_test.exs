defmodule GenSpoxy.Cache.StressTests do
  use ExUnit.Case, async: false

  alias GenSpoxy.Stores.Ets

  import Macros.Tests

  defprerender(
    Stress.SamplePrerender,
    do_req: fn req ->
      :timer.sleep(200)
      {:ok, "response for #{inspect(req)}"}
    end
  )

  defmodule Stress.SampleCache do
    use GenSpoxy.Cache, prerender_module: Stress.SamplePrerender
  end

  setup_all do
    Ets.Supervisor.start_link()
    Stress.SamplePrerender.Supervisor.start_link()
    :ok
  end

  setup do
    Ets.reset_all!()
    Ets.Supervisor.start_link()
    :ok
  end

  test "multiple concurrent clients calling the same request" do
    n = 1000

    table_name = "table-prerender-cache-stress-1"
    req = ["req-prerender-cache-stress-1", "newest"]
    ttl_ms = 100

    assert {:miss, _reason} = Stress.SampleCache.get(req, table_name: table_name)

    opts = [table_name: table_name, do_janitor_work: false, blocking: true, ttl_ms: ttl_ms]

    active_task = Stress.SampleCache.async_get_or_fetch(req, opts)

    passive_tasks =
      Enum.map(2..n, fn _ ->
        Stress.SampleCache.async_get_or_fetch(req, opts)
      end)

    Enum.each(passive_tasks, fn task ->
      {:ok, "response for [\"req-prerender-cache-stress-1\", \"newest\"]", _bench} =
        Stress.SampleCache.await(task)
    end)

    {:ok, "response for [\"req-prerender-cache-stress-1\", \"newest\"]", _bench} =
      Stress.SampleCache.await(active_task)
  end
end
