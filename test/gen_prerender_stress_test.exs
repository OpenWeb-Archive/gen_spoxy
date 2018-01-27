defmodule GenSpoxy.Prerender.StressTests do
  use ExUnit.Case

  import GenSpoxy.Prerender.Macros

  defprerender(
    StressedPrerender,
    do_req: fn req ->
      :timer.sleep(300)
      {:ok, "response for #{inspect(req)}"}
    end
  )

  setup_all do
    StressedPrerender.Supervisor.start_link()
    :ok
  end

  test "multiple concurrent clients calling the same request" do
    n = 1000
    req = ["prerender-stress-1", "newest"]

    active_task = Task.async(fn -> StressedPrerender.perform(req) end)

    :timer.sleep(100)

    passive_tasks =
      Enum.map(2..n, fn _ ->
        Task.async(fn -> StressedPrerender.perform(req) end)
      end)

    Enum.each(passive_tasks, fn task ->
      {{:ok, "response for [\"prerender-stress-1\", \"newest\"]"}, :passive} = Task.await(task)
    end)

    {{:ok, "response for [\"prerender-stress-1\", \"newest\"]"}, :active} =
      Task.await(active_task)
  end
end
