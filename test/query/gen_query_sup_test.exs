defmodule GenSpoxy.Query.Supervisor.Tests do
  use ExUnit.Case, async: false

  import Macros.Tests

  defquery(SupervisedQuery, do_req: fn _ -> :ok end)

  setup_all do
    SupervisedQuery.Supervisor.start_link()
    :ok
  end

  test "all children are of type `query_module`" do
    query_module = GenSpoxy.Query.Supervisor.Tests.SupervisedQuery
    total_partitions = SupervisedQuery.total_partitions()

    children = Supervisor.which_children(SupervisedQuery.Supervisor)

    # asserting all childern are of `query_module`
    children
    |> Enum.with_index(0)
    |> Enum.each(fn {child, i} ->
      partition = total_partitions - i
      child_name = "#{query_module}-#{partition}"
      assert {^child_name, _worker_pid, :worker, [^query_module]} = child
    end)
  end

  test "auto-restarts terminated children" do
    query_module = GenSpoxy.Query.Supervisor.Tests.SupervisedQuery

    children = Supervisor.which_children(SupervisedQuery.Supervisor)

    {_, worker_pid, _, _} =
      Enum.find(children, fn child ->
        {child_name, _, :worker, [^query_module]} = child
        child_name == "#{query_module}-5"
      end)

    ref = Process.monitor(worker_pid)

    Process.exit(worker_pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^worker_pid, :killed} -> ""
    end

    children = Supervisor.which_children(SupervisedQuery.Supervisor)

    {_, worker_pid_new, _, _} =
      Enum.find(children, fn child ->
        {child_name, _, :worker, [^query_module]} = child
        child_name == "#{query_module}-5"
      end)

    refute worker_pid == worker_pid_new
  end
end
