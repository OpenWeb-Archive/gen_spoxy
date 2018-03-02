defmodule GenSpoxy.Prerender.Tests do
  use ExUnit.Case

  import ExUnit.CaptureLog
  import Macros.Tests

  defprerender(FastPrerender, do_req: fn req -> {:ok, "response for #{inspect(req)}"} end)

  defprerender(
    SlowPrerender,
    do_req: fn req ->
      :timer.sleep(SlowPrerender.sample_task_interval() + 50)
      {:ok, "response for #{inspect(req)}"}
    end
  )

  defprerender(FrozenPrerender, do_req: fn _ -> :timer.sleep(:infinity) end)
  defprerender(FailingPrerender, do_req: fn _ -> {:error, "error occurred"} end)
  defprerender(RaisingErrorsPrerender, do_req: fn _ -> raise "oops..." end)

  test "fast-prerender, cleanup will take place after 1st sampling" do
    {:ok, pid} = FastPrerender.Supervisor.start_link()

    fun = fn ->
      req = ["req-fast-1", "newest"]
      resp = FastPrerender.perform(req)
      assert resp == {{:ok, "response for [\"req-fast-1\", \"newest\"]"}, :active}

      state = FastPrerender.get_req_state(req)

      # assert `reqs_state` is empty
      assert Map.get(state, :reqs_state) == %{}

      # cleanup hasn't been executed yet
      refute %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state

      # 1st sample takes place after `sample_task_interval`, so we'll wait a bit longer
      # to let the cleanup process execute for sure
      :timer.sleep(FastPrerender.sample_task_interval() + 50)

      # cleanup has been executed
      state = FastPrerender.get_req_state(req)

      assert %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state
    end

    assert capture_log(fun) =~ "1st sample task: performing cleanup"

    {:error, {:already_started, ^pid}} = FastPrerender.Supervisor.start_link()
  end

  test "slow prerender, cleanup will take place after the 2nd sample" do
    {:ok, pid} = SlowPrerender.Supervisor.start_link()

    fun = fn ->
      req = ["req-slow-1", "newest"]
      resp = SlowPrerender.perform(req)
      assert resp == {{:ok, "response for [\"req-slow-1\", \"newest\"]"}, :active}

      state = SlowPrerender.get_req_state(req)

      # assert `reqs_state` is empty
      assert Map.get(state, :reqs_state) == %{}

      :timer.sleep(SlowPrerender.sample_task_interval() + 50)

      # cleanup has been executed
      state = SlowPrerender.get_req_state(req)
      assert %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state
    end

    assert capture_log(fun) =~ "2nd sample task: performing cleanup"

    {:error, {:already_started, ^pid}} = SlowPrerender.Supervisor.start_link()
  end

  test "raising errors prerender, cleanup will take place after 1st sampling" do
    {:ok, pid} = RaisingErrorsPrerender.Supervisor.start_link()

    fun = fn ->
      req = ["req-raising-1", "newest"]
      assert {{:error, "error occurred"}, :active} == RaisingErrorsPrerender.perform(req)

      state = RaisingErrorsPrerender.get_req_state(req)

      # cleanup hasn been executed
      assert %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state
    end

    # silencing the error raised by `RaisingErrorsPrerender`
    capture_log(fun)

    {:error, {:already_started, ^pid}} = RaisingErrorsPrerender.Supervisor.start_link()
  end

  test "failing prerender, cleanup will take place after 1st sampling" do
    {:ok, pid} = FailingPrerender.Supervisor.start_link()

    fun = fn ->
      req = ["req-failing-1", "newest"]
      resp = FailingPrerender.perform(req)
      assert resp == {{:error, "error occurred"}, :active}

      state = FailingPrerender.get_req_state(req)

      # assert `reqs_state` is empty
      assert %{reqs_state: %{}} = state

      # cleanup hasn't been executed yet
      refute %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state

      # 1st sample takes place after `sample_task_interval`, so we'll wait a bit longer
      # to let the cleanup process execute
      :timer.sleep(FailingPrerender.sample_task_interval())

      # cleanup has been executed
      state = FailingPrerender.get_req_state(req)
      assert %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}} == state
    end

    assert capture_log(fun) =~ "1st sample task: performing cleanup"

    {:error, {:already_started, ^pid}} = FailingPrerender.Supervisor.start_link()
  end

  test "frozen prerender, cleanup will brutally kill the task" do
    {:ok, pid} = FrozenPrerender.Supervisor.start_link()

    fun = fn ->
      try do
        FrozenPrerender.perform(["req-frozen-1", "newest"])
      catch
        :exit, {:timeout, _} -> ""
      end
    end

    assert capture_log(fun) =~
             "2nd sample task: performing full cleanup ([delete_req_state: true, shutdown_task: true])"

    {:error, {:already_started, ^pid}} = FrozenPrerender.Supervisor.start_link()
  end
end
