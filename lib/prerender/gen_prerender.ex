defmodule GenSpoxy.Prerender do
  @moduledoc """
  a behaviour for defining prerender
  """

  defmacro __using__(opts) do
    quote do
      use GenSpoxy.Partitionable

      alias Spoxy.Prerender.Server

      @behaviour Spoxy.Prerender.Behaviour

      @default_timeout  Keyword.get(unquote(opts),
                                    :prerender_timeout,
                                    GenSpoxy.Constants.prerender_timeout()
                                    )

      @total_partitions Keyword.get(unquote(opts),
                                    :total_partitions,
                                    GenSpoxy.Constants.total_partitions())

      @sample_interval Keyword.get(unquote(opts),
                                        :prerender_sampling_interval,
                                        GenSpoxy.Constants.prerender_sampling_interval()
                                        )

      def start_link(opts) do
        Server.start_link(opts)
      end

      def perform(req) do
        server = lookup_server_name(req)
        req_key = calc_req_key(req)

        opts = [timeout: @default_timeout, interval: @sample_interval]

        Server.perform(server, __MODULE__, req, req_key, opts)
      end

      def sample_task_interval do
        @sample_interval
      end

      @impl true
      def calc_req_partition(req_key) do
        1 + :erlang.phash2(req_key, total_partitions())
      end

      @doc """
      used for testing
      """
      def get_req_state(req) do
        partition = req_partition(req)
        get_partition_state(partition)
      end

      @impl true
      def total_partitions do
        @total_partitions
      end

      @doc """
      used for testing
      """
      def get_partition_state(partition) do
        server = partition_server(partition)

        Server.get_partition_state(server)
      end

      def req_partition(req) do
        req_key = calc_req_key(req)
        calc_req_partition(req_key)
      end

      def inspect_all_partitions do
        initial_state = %{total_listeners: 0, total_passive: 0}

        Enum.reduce(1..@total_partitions, initial_state, fn partition, acc ->
          {:ok, total_listeners} = Map.fetch(acc, :total_listeners)
          {:ok, total_passive} = Map.fetch(acc, :total_passive)

          partition_data = inspect_partition(partition)

          {:ok, listeners} = Map.fetch(partition_data, :total_listeners)
          {:ok, passive} = Map.fetch(partition_data, :total_passive)

          new_total_listeners = total_listeners + listeners
          new_total_passive = total_passive + passive

          acc
          |> Map.put(:total_listeners, new_total_listeners)
          |> Map.put(:total_passive, new_total_passive)
        end)
      end

      @doc """
      returns for `partition` the total number of listeners across all the partition requests
      and how many of them are passive listeners
      """
      def inspect_partition(partition) do
        %{reqs_state: reqs_state} = get_partition_state(partition)

        initial_state = %{total_listeners: 0, total_passive: 0}

        Enum.reduce(reqs_state, initial_state, fn {_req_key, req_state}, acc ->
          {:ok, total_listeners} = Map.fetch(acc, :total_listeners)
          {:ok, total_passive} = Map.fetch(acc, :total_passive)

          %{listeners: listeners} = req_state

          passive = for {:passive, listener} <- listeners, do: listener

          new_total_listeners = total_listeners + Enum.count(listeners)
          new_total_passive = total_passive + Enum.count(passive)

          acc
          |> Map.put(:total_listeners, new_total_listeners)
          |> Map.put(:total_passive, new_total_passive)
        end)
      end

      defp lookup_server_name(req) do
        partition = req_partition(req)

        partition_server(partition)
      end

      prerender_module = __MODULE__
      prerender_sup_module = String.to_atom("#{prerender_module}.Supervisor")

      defmodule prerender_sup_module do
        use GenSpoxy.Prerender.Supervisor, supervised_module: prerender_module
      end
    end
  end
end
