defmodule GenSpoxy.Periodic.TasksExecutor.Tests do
  use ExUnit.Case, async: false

  import Macros.Tests

  alias GenSpoxy.Stores.Ets

  defprerender(
    Periodic.SamplePrerender,
    do_req: fn req ->
      :timer.sleep(300)
      {:ok, "response for #{inspect(req)}"}
    end
  )

  defmodule Periodic.SampleCache do
    use GenSpoxy.Cache,
      store_module: Ets,
      prerender_module: Periodic.SamplePrerender
  end

  defmodule SampleCacheTasksExecutor do
    use GenSpoxy.Prerender.PeriodicTasksExecutor,
      cache_module: Periodic.SampleCache,
      total_partitions: 1,
      sampling_interval: 200
  end

  setup_all do
    Ets.Supervisor.start_link()
    Periodic.SamplePrerender.Supervisor.start_link()
    :ok
  end

  @tag :skip
  test "executes the enqueued taks periodically" do
    req = ["periodic-test-1", "newest"]
    req_key = "req-1"
    opts = [table_name: "table-periodic-1", ttl_ms: 1000]

    partition = SampleCacheTasksExecutor.calc_req_partition(req_key)
    server_name = SampleCacheTasksExecutor.partition_server(partition)

    {:ok, _pid} = SampleCacheTasksExecutor.start_link(name: server_name)

    Enum.each(1..10, fn _ ->
      SampleCacheTasksExecutor.enqueue_task(req_key, [req, opts])
    end)

    :timer.sleep(2000)
    Periodic.SamplePrerender.inspect_all_partitions()
    # %{total_listeners: 10, total_passive: 9} = Periodic.SamplePrerender.inspect_all_partitions()

    # :timer.sleep(300)
    # %{total_listeners: 0, total_passive: 0} = Periodic.SamplePrerender.inspect_all_partitions()
    #
    # Enum.each(1..100, fn _ ->
    #   SampleCacheTasksExecutor.enqueue_task(req_key, [req, opts])
    # end)
    #
    # :timer.sleep(300)
    # %{total_listeners: 100, total_passive: 99} = Periodic.SamplePrerender.inspect_all_partitions()
  end
end
