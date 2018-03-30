defmodule GenSpoxy.Query.StressTests do
  use ExUnit.Case, async: false

  import Macros.Tests

  defquery(
    StressedQuery,
    do_req: fn req ->
      :timer.sleep(300)
      {:ok, "response for #{inspect(req)}"}
    end
  )

  setup_all do
    StressedQuery.Supervisor.start_link()
    :ok
  end

  test "multiple concurrent clients calling the same request" do
    n = 1000
    req = ["query-stress-1", "newest"]

    active_task = Task.async(fn -> StressedQuery.perform(req) end)

    :timer.sleep(100)

    passive_tasks =
      Enum.map(2..n, fn _ ->
        Task.async(fn -> StressedQuery.perform(req) end)
      end)

    Enum.each(passive_tasks, fn task ->
      {{:ok, "response for [\"query-stress-1\", \"newest\"]"}, :passive} = Task.await(task)
    end)

    {{:ok, "response for [\"query-stress-1\", \"newest\"]"}, :active} =
      Task.await(active_task)
  end
end
