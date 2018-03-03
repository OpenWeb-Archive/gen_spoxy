defmodule GenSpoxy.Periodic.TasksExecutor do
  @moduledoc """
  a behaviour for running prerender tasks periodically.

  when we execute a `spoxy` reqeust and have a cache miss returning a stale date,
  we may choose to return the stale data and queue a background task.
  """

  @callback execute_tasks!(req_key :: String.t(), req_tasks :: Array) :: :ok

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use GenServer
      use GenSpoxy.Partitionable

      alias GenSpoxy.Defaults

      @sampling_interval Keyword.get(
                           opts,
                           :periodic_sampling_interval,
                           Defaults.periodic_sampling_interval()
                         )

      default_partitions =
        Keyword.get(
          opts,
          :total_partitions,
          Defaults.total_partitions()
        )

      @total_partitions Keyword.get(
                          opts,
                          :periodic_total_partitions,
                          default_partitions
                        )

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, opts)
      end

      def enqueue_task(req_key, task) do
        server = lookup_req_server(req_key)
        GenServer.cast(server, {:enqueue_task, req_key, task})
      end

      # callbacks
      @impl true
      def init(_opts) do
        Process.send_after(self(), :execute_tasks, @sampling_interval)

        {:ok, %{}}
      end

      @impl true
      def handle_cast({:enqueue_task, req_key, task}, state) do
        req_tasks = Map.get(state, req_key, [])
        new_state = Map.put(state, req_key, [task | req_tasks])

        {:noreply, new_state}
      end

      @impl true
      def handle_info(:execute_tasks, state) do
        Process.send_after(self(), :execute_tasks, @sampling_interval)

        Enum.each(state, fn {req_key, req_tasks} ->
          Task.start(fn ->
            execute_tasks!(req_key, req_tasks)
          end)
        end)

        {:noreply, %{}}
      end

      @impl true
      def total_partitions do
        @total_partitions
      end

      @impl true
      def calc_req_partition(req_key) do
        1 + :erlang.phash2(req_key, @total_partitions)
      end

      defp lookup_req_server(req_key) do
        partition = calc_req_partition(req_key)

        partition_server(partition)
      end
    end
  end
end
