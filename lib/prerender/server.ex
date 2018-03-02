defmodule Spoxy.Prerender.Server do
  @moduledoc """
  Prender logic
  """

  use GenServer

  require Logger

  @sample_task_interval GenSpoxy.Constants.default_prerender_sampling_interval()

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def perform(server, prerender_module, req, req_key, timeout) do
    GenServer.call(server, {:perform, prerender_module, req, req_key}, timeout)
  end

  def get_partition_state(server) do
    GenServer.call(server, :get_state)
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    state = %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}}

    {:ok, state}
  end

  # callbacks
  @impl true
  def handle_call({:perform, prerender_module, req, req_key}, from, state) do
    {:ok, pid_ref} = Map.fetch(state, :pid_ref)
    {:ok, refs_resp} = Map.fetch(state, :refs_resp)
    {:ok, refs_req} = Map.fetch(state, :refs_req)
    {:ok, reqs_state} = Map.fetch(state, :reqs_state)

    not_started_state = %{listeners: [], status: :not_started}
    req_state = Map.get(reqs_state, req_key, not_started_state)

    %{listeners: listeners, status: status} = req_state

    {new_req_state, new_pid_ref, new_refs_req} =
      case status do
        :not_started ->
          task = Task.async(prerender_module, :do_req, [req])
          %Task{ref: ref, pid: pid} = task

          # we first assert that `ref` and `pid` aren't in use.
          # *we handling theoretical `pid`/`ref` collisions)
          # if such case happens it'll probably implies a bug
          if Map.has_key?(pid_ref, pid) || Map.has_key?(refs_resp, ref) ||
               Map.has_key?(refs_req, ref) do
            # this should never really happen
            Logger.error("resources (pid/ref) collisions")

            Process.exit(pid, :kill)

            raise "fatal error"
          end

          task = %{pid: pid, ref: ref}

          # we'll sample the task completion status
          # in `sample_task_interval` ms from now
          schedule_sample_task(task, 1, @sample_task_interval)

          new_running_req_state = %{
            listeners: [{:active, from}],
            status: :running,
            task: task
          }

          {new_running_req_state, Map.put_new(pid_ref, pid, ref),
           Map.put_new(refs_req, ref, req_key)}

        :running ->
          new_listeners = [{:passive, from} | listeners]
          {%{req_state | listeners: new_listeners}, pid_ref, refs_req}

        _ ->
          raise "unknown req status: '#{status}'"
      end

    new_reqs_state = Map.put(reqs_state, req_key, new_req_state)

    new_state = %{
      state
      | pid_ref: new_pid_ref,
        refs_req: new_refs_req,
        reqs_state: new_reqs_state
    }

    # the `handle_info` method will reply to `from` in the future.
    # so we return `:noreply` for now. (see: `handle_info({ref, resp}, state)`)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # this method expects the response of the prerender task
  @impl true
  def handle_info({ref, resp}, state) do
    %{refs_resp: refs_resp, refs_req: refs_req, reqs_state: reqs_state} = state

    new_refs_resp = Map.put_new(refs_resp, ref, resp)
    req_key = Map.get(refs_req, ref)
    req_state = Map.get(reqs_state, req_key)

    %{listeners: listeners} = req_state

    notify_listeners(listeners, resp)

    # we do a cleanup for the request state
    # the rest of the cleanup will be done in `do_cleanup`
    new_reqs_state = Map.delete(reqs_state, req_key)

    new_state = %{state | refs_resp: new_refs_resp, reqs_state: new_reqs_state}

    {:noreply, new_state}
  end

  # here we sample for the 1st time a running prerender task.
  # In case the task has been completed we cleanup its resources,
  # else, we schedule a 2nd and final sample in the future

  @impl true
  def handle_info(
        {:sample_task, %{ref: ref} = task, 1 = _iteration},
        %{refs_resp: refs_resp} = state
      ) do
    if Map.has_key?(refs_resp, ref) do
      Logger.info("1st sample task: performing cleanup for a terminated task")

      {:noreply, _} =
        do_cleanup(task, state, delete_req_state: false, shutdown_task: false)
    else
      # task didn't finish...
      # we're going to sample it again in `sample_task_interval` ms
      schedule_sample_task(task, 2, @sample_task_interval)
      {:noreply, state}
    end
  end

  # Here we perform the 2nd and final sample for a prerender task.
  # If the task has been completed we are left with cleaning up its resources,
  # else, if task is still on-going (should be a very rare case),
  # we'll brutally kill it and then cleanup the associated resources.

  @impl true
  def handle_info(
        {:sample_task, %{ref: ref} = task, 2 = _iteration},
        %{refs_resp: refs_resp} = state
      ) do
    {:noreply, _} =
      if Map.has_key?(refs_resp, ref) do
        Logger.info("2nd sample task: performing cleanup for a terminated task")

        {:noreply, _} =
          do_cleanup(task, state, delete_req_state: false, shutdown_task: false)
      else
        # seems the task is taking too much time...
        # we'll shut it down brutally and reset its state

        opts = [delete_req_state: true, shutdown_task: true]

        Logger.info("2nd sample task: performing full cleanup (#{inspect(opts)})")

        {:noreply, _} = do_cleanup(task, state, opts)
      end
  end

  @impl true
  def handle_info({:EXIT, pid, {_error, _stacktrace}}, state) do
    %{pid_ref: pid_ref, refs_req: refs_req, reqs_state: reqs_state} = state

    ref = Map.get(pid_ref, pid)
    req_key = Map.get(refs_req, ref)
    req_state = Map.get(reqs_state, req_key)

    %{listeners: listeners} = req_state

    notify_listeners(listeners, {:error, "error occurred"})

    cleanup_opts = [delete_req_state: true, shutdown_task: false]
    {:noreply, _} = do_cleanup(%{ref: ref, pid: pid}, state, cleanup_opts)
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def sample_task_interval do
    @sample_task_interval
  end

  ## private
  defp do_cleanup(%{ref: ref, pid: pid}, state, opts) do
    {:ok, pid_ref} = Map.fetch(state, :pid_ref)
    {:ok, refs_resp} = Map.fetch(state, :refs_resp)
    {:ok, refs_req} = Map.fetch(state, :refs_req)
    {:ok, reqs_state} = Map.fetch(state, :reqs_state)

    req_key = Map.get(refs_req, ref)

    new_refs_resp = Map.delete(refs_resp, ref)
    new_pid_ref = Map.delete(pid_ref, pid)
    new_refs_req = Map.delete(refs_req, ref)

    shutdown_task = Keyword.get(opts, :shutdown_task, false)
    delete_req_state = Keyword.get(opts, :delete_req_state, false)

    new_reqs_state =
      if delete_req_state do
        Map.delete(reqs_state, req_key)
      else
        reqs_state
      end

    if shutdown_task do
      Process.exit(pid, :kill)
    end

    new_state = %{
      pid_ref: new_pid_ref,
      refs_resp: new_refs_resp,
      refs_req: new_refs_req,
      reqs_state: new_reqs_state
    }

    {:noreply, new_state}
  end

  defp notify_listeners(listeners, resp) do
    for {active_or_passive, from} <- listeners do
      GenServer.reply(from, {resp, active_or_passive})
    end
  end

  defp schedule_sample_task(task, iteration, time) do
    Process.send_after(self(), {:sample_task, task, iteration}, time)
  end
end
