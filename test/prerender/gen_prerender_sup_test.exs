defmodule GenSpoxy.Prerender.Supervisor.Tests do
  use ExUnit.Case, async: false

  import Macros.Tests

  defprerender(SupervisedPrerender, do_req: fn _ -> :ok end)

  setup_all do
    SupervisedPrerender.Supervisor.start_link()
    :ok
  end

  test "all children are of type `prerender_module`" do
    prerender_module = GenSpoxy.Prerender.Supervisor.Tests.SupervisedPrerender
    total_partitions = SupervisedPrerender.total_partitions()

    children = Supervisor.which_children(SupervisedPrerender.Supervisor)

    # asserting all childern are of `prerender_module`
    children
    |> Enum.with_index(0)
    |> Enum.each(fn {child, i} ->
      partition = total_partitions - i
      child_name = "#{prerender_module}-#{partition}"
      assert {^child_name, _worker_pid, :worker, [^prerender_module]} = child
    end)
  end

  test "auto-restarts terminated children" do
    prerender_module = GenSpoxy.Prerender.Supervisor.Tests.SupervisedPrerender

    children = Supervisor.which_children(SupervisedPrerender.Supervisor)

    {_, worker_pid, _, _} =
      Enum.find(children, fn child ->
        {child_name, _, :worker, [^prerender_module]} = child
        child_name == "#{prerender_module}-5"
      end)

    ref = Process.monitor(worker_pid)

    Process.exit(worker_pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^worker_pid, :killed} -> ""
    end

    children = Supervisor.which_children(SupervisedPrerender.Supervisor)

    {_, worker_pid_new, _, _} =
      Enum.find(children, fn child ->
        {child_name, _, :worker, [^prerender_module]} = child
        child_name == "#{prerender_module}-5"
      end)

    refute worker_pid == worker_pid_new
  end
end
