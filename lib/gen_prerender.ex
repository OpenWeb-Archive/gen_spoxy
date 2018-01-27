defmodule GenSpoxy.Prerender do
  @moduledoc """
  a behaviour for defining prerender
  """

  @doc """
  executing the request itself
  """
  @callback do_req(req :: any) :: {:ok, any} | {:error, any}

  @doc """
  calculating the request signature (must be a deterministic calculation)
  i.e: given a `req` input, always returns the same `req_key`
  """
  @callback calc_req_key(req :: any) :: String.t()

  defmacro __using__(_opts) do
    quote do
      use GenServer
      use GenSpoxy.Partitionable

      require Logger

      @behaviour GenSpoxy.Prerender

      @total_partitions GenSpoxy.Constants.total_partitions(:gen_prerender)
      @perform_default_timeout GenSpoxy.Constants.default_prerender_timeout()
      @sample_task_interval GenSpoxy.Constants.default_prerender_sampling_interval()

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, opts)
      end

      # Server API
      def perform(req, opts \\ []) do
        GenServer.call(lookup_server_name(req), {:perform, req}, @perform_default_timeout)
      end

      def sample_task_interval do
        @sample_task_interval
      end

      def req_partition(req) do
        req_key = calc_req_key(req)
        calc_req_partition(req_key)
      end

      @impl true
      def init(_opts) do
        Process.flag(:trap_exit, true)

        state = %{pid_ref: %{}, refs_resp: %{}, refs_req: %{}, reqs_state: %{}}

        {:ok, state}
      end

      @doc """
      used for testing
      """
      def get_req_state(req) do
        partition = req_partition(req)
        get_partition_state(partition)
      end

      @doc """
      used for testing
      """
      def get_partition_state(partition) do
        GenServer.call(partition_server(partition), :get_state)
      end

      def inspect_all_partitions() do
        Enum.reduce(1..@total_partitions, %{total_listeners: 0, total_passive: 0}, fn partition,
                                                                                      acc ->
          %{total_listeners: partition_total, total_passive: partition_passive} =
            inspect_partition(partition)

          %{total_listeners: total_listeners, total_passive: total_passive} = acc

          %{
            acc
            | total_listeners: total_listeners + partition_total,
              total_passive: total_passive + partition_passive
          }
        end)
      end

      @doc """
      returns for `partition` the total number of listeners across all the partition requests
      and how many of them are passive listeners
      """
      def inspect_partition(partition) do
        %{reqs_state: reqs_state} = get_partition_state(partition)

        Enum.reduce(reqs_state, %{total_listeners: 0, total_passive: 0}, fn {_req_key, req_state},
                                                                            acc ->
          %{total_listeners: total_listeners, total_passive: total_passive} = acc
          %{listeners: listeners} = req_state

          passive = for {:passive, listener} <- listeners, do: listener

          %{
            acc
            | total_listeners: total_listeners + Enum.count(listeners),
              total_passive: total_passive + Enum.count(passive)
          }
        end)
      end

      # Callbacks
      @impl true
      def handle_call(:get_state, from, state) do
        {:reply, state, state}
      end

      @impl true
      def handle_call({:perform, req}, from, state) do
        %{pid_ref: pid_ref, refs_resp: refs_resp, refs_req: refs_req, reqs_state: reqs_state} =
          state

        req_key = calc_req_key(req)
        req_state = Map.get(reqs_state, req_key, %{listeners: [], status: :not_started})

        %{listeners: listeners, status: status} = req_state

        {new_req_state, new_pid_ref, new_refs_req} =
          case status do
            :not_started ->
              %Task{ref: ref, pid: pid} = Task.async(__MODULE__, :do_req, [req])

              # we first assert that `ref` and `pid` aren't in use (handling theoretical `pid`/`ref` collisions due to erlang VM reuse)
              if Map.has_key?(pid_ref, pid) || Map.has_key?(refs_resp, ref) ||
                   Map.has_key?(refs_req, ref) do
                # this should never really happen
                # see: https://stackoverflow.com/questions/46138098/can-erlang-reuse-process-ids-if-so-how-to-be-sure-of-correctness
                Logger.error("resources (pid/ref) collisions")

                Process.exit(pid, :kill)

                raise "fatal error"
              end

              task = %{pid: pid, ref: ref}

              new_refs_req = Map.put_new(refs_req, ref, req_key)

              # we'll sample the task completion status in `sample_task_interval` ms from now
              schedule_sample_task(task, 1, @sample_task_interval)

              new_running_req_state = %{
                listeners: [{:active, from}],
                status: :running,
                task: task
              }

              {new_running_req_state, Map.put_new(pid_ref, pid, ref),
               Map.put_new(refs_req, ref, req_key)}

            :running ->
              {%{req_state | listeners: [{:passive, from} | listeners]}, pid_ref, refs_req}

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

        # the `handle_info` method will reply to `from` in the future (see: `handle_info({ref, resp}, state)`)
        # so we return `:noreply` for now
        {:noreply, new_state}
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
            {:sample_task, %{ref: ref} = task, 1 = iteration},
            %{refs_resp: refs_resp} = state
          ) do
        if Map.has_key?(refs_resp, ref) do
          Logger.info("1st sample task: performing cleanup for a terminated task")

          {:noreply, new_state} =
            do_cleanup(task, state, delete_req_state: false, shutdown_task: false)
        else
          # task didn't finish... so we're going to sample it again in `sample_task_interval` ms
          schedule_sample_task(task, 2, @sample_task_interval)
          {:noreply, state}
        end
      end

      # Here we perform the 2nd and final sample for a prerender task.
      # If the task has been completed we are left with cleaning up its resources,
      # else, if task is still on-going (should be a very rare case), we brutally kill it
      # and then cleanup the associated resources.

      @impl true
      def handle_info(
            {:sample_task, %{ref: ref, pid: pid} = task, 2 = iteration},
            %{refs_resp: refs_resp} = state
          ) do
        {:noreply, new_state} =
          if Map.has_key?(refs_resp, ref) do
            Logger.info("2nd sample task: performing cleanup for a terminated task")

            {:noreply, new_state} =
              do_cleanup(task, state, delete_req_state: false, shutdown_task: false)
          else
            # seems the task is taking too much time, so we'll shut it down brutally and reset its state

            opts = [delete_req_state: true, shutdown_task: true]

            Logger.info("2nd sample task: performing full cleanup (#{inspect(opts)})")

            {:noreply, new_state} = do_cleanup(task, state, opts)
          end
      end

      @impl true
      def handle_info({:EXIT, pid, {_error, _stacktrace}}, state) do
        %{pid_ref: pid_ref, refs_req: refs_req, reqs_state: reqs_state} = state

        %{refs_req: refs_req, reqs_state: reqs_state} = state

        ref = Map.get(pid_ref, pid)
        req_key = Map.get(refs_req, ref)
        req_state = Map.get(reqs_state, req_key)

        %{listeners: listeners} = req_state

        notify_listeners(listeners, {:error, "error occurred"})

        {:noreply, new_state} =
          do_cleanup(%{ref: ref, pid: pid}, state, delete_req_state: true, shutdown_task: false)
      end

      def handle_info(_msg, state) do
        {:noreply, state}
      end

      defp schedule_sample_task(task, iteration, time) do
        Process.send_after(self(), {:sample_task, task, iteration}, time)
      end

      defp do_cleanup(%{ref: ref, pid: pid} = task, state, opts \\ []) do
        %{pid_ref: pid_ref, refs_resp: refs_resp, refs_req: refs_req, reqs_state: reqs_state} =
          state

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
          %{pid: pid} = task

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

      defp lookup_server_name(req) do
        partition = req_partition(req)

        partition_server(partition)
      end

      @impl true
      def total_partitions() do
        @total_partitions
      end

      @impl true
      def calc_req_partition(req_key) do
        1 + :erlang.phash2(req_key, total_partitions())
      end

      defp notify_listeners(listeners, resp) do
        for {active_or_passive, from} <- listeners do
          GenServer.reply(from, {resp, active_or_passive})
        end
      end

      prerender_module = __MODULE__
      prerender_sup_module = String.to_atom("#{prerender_module}.Supervisor")

      defmodule prerender_sup_module do
        use GenSpoxy.Prerender.Supervisor, supervised_module: prerender_module
      end
    end
  end
end
