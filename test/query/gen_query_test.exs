defmodule GenSpoxy.Query.Tests do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Macros.Tests

  defquery(FastQuery, do_req: fn req -> {:ok, "response for #{inspect(req)}"} end)

  defquery(
    SlowQuery,
    do_req: fn req ->
      :timer.sleep(SlowQuery.sample_task_interval() + 50)
      {:ok, "response for #{inspect(req)}"}
    end
  )

  defquery(FrozenQuery, do_req: fn _ -> :timer.sleep(:infinity) end)
  defquery(FailingQuery, do_req: fn _ -> {:error, "error occurred"} end)
  defquery(RaisingQuery, do_req: fn _ -> raise "oops..." end)

  test "fast-query, cleanup will take place after 1st sampling" do
    {:ok, pid} = FastQuery.Supervisor.start_link()

    fun = fn ->
      req = ["req-fast-1", "newest"]
      resp = FastQuery.perform(req)
      assert resp == {{:ok, "response for [\"req-fast-1\", \"newest\"]"}, :active}

      state = FastQuery.get_req_state(req)

      # assert `reqs_state` is empty
      assert Map.get(state, :reqs_state) == %{}

      # cleanup hasn't been executed yet
      refute %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state

      # 1st sample takes place after `sample_task_interval`, so we'll wait a bit longer
      # to let the cleanup process execute for sure
      :timer.sleep(FastQuery.sample_task_interval() + 50)

      # cleanup has been executed
      state = FastQuery.get_req_state(req)

      assert %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state
    end

    assert capture_log(fun) =~ "1st sample task: performing cleanup"

    {:error, {:already_started, ^pid}} = FastQuery.Supervisor.start_link()
  end

  test "slow query, cleanup will take place after the 2nd sample" do
    {:ok, pid} = SlowQuery.Supervisor.start_link()

    fun = fn ->
      req = ["req-slow-1", "newest"]
      resp = SlowQuery.perform(req)
      assert resp == {{:ok, "response for [\"req-slow-1\", \"newest\"]"}, :active}

      state = SlowQuery.get_req_state(req)

      # assert `reqs_state` is empty
      assert Map.get(state, :reqs_state) == %{}

      :timer.sleep(SlowQuery.sample_task_interval() + 50)

      # cleanup has been executed
      state = SlowQuery.get_req_state(req)
      assert %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state
    end

    assert capture_log(fun) =~ "2nd sample task: performing cleanup"

    {:error, {:already_started, ^pid}} = SlowQuery.Supervisor.start_link()
  end

  test "raising errors query, cleanup will take place after 1st sampling" do
    {:ok, pid} = RaisingQuery.Supervisor.start_link()

    fun = fn ->
      req = ["req-raising-1", "newest"]
      assert {{:error, "error occurred"}, :active} == RaisingQuery.perform(req)

      state = RaisingQuery.get_req_state(req)

      # cleanup hasn been executed
      assert %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state
    end

    # silencing the error raised by `RaisingQuery`
    capture_log(fun)

    {:error, {:already_started, ^pid}} = RaisingQuery.Supervisor.start_link()
  end

  test "failing query, cleanup will take place after 1st sampling" do
    {:ok, pid} = FailingQuery.Supervisor.start_link()

    fun = fn ->
      req = ["req-failing-1", "newest"]
      resp = FailingQuery.perform(req)
      assert resp == {{:error, "error occurred"}, :active}

      state = FailingQuery.get_req_state(req)

      # assert `reqs_state` is empty
      assert %{reqs_state: %{}} = state

      # cleanup hasn't been executed yet
      refute %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state

      # 1st sample takes place after `sample_task_interval`, so we'll wait a bit longer
      # to let the cleanup process execute
      :timer.sleep(FailingQuery.sample_task_interval())

      # cleanup has been executed
      state = FailingQuery.get_req_state(req)
      assert %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state
    end

    assert capture_log(fun) =~ "1st sample task: performing cleanup"

    {:error, {:already_started, ^pid}} = FailingQuery.Supervisor.start_link()
  end

  test "frozen query, cleanup will brutally kill the task" do
    {:ok, pid} = FrozenQuery.Supervisor.start_link()

    fun = fn ->
      try do
        FrozenQuery.perform(["req-frozen-1", "newest"])
      catch
        :exit, {:timeout, _} -> ""
      end
    end

    assert capture_log(fun) =~
             "2nd sample task: performing full cleanup ([delete_req_state: true, shutdown_task: true])"

    {:error, {:already_started, ^pid}} = FrozenQuery.Supervisor.start_link()
  end
end
