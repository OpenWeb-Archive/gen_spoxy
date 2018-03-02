defmodule GenSpoxy.Prerender do
  @moduledoc """
  a behaviour for defining prerender
  """

  defmacro __using__(_opts) do
    quote do
      use GenSpoxy.Partitionable

      @behaviour Spoxy.Prerender.Behaviour

      @perform_default_timeout GenSpoxy.Constants.default_prerender_timeout()
      @total_partitions GenSpoxy.Constants.total_partitions(:gen_prerender)

      def start_link(opts) do
        Spoxy.Prerender.Server.start_link(opts)
      end

      def perform(req, opts \\ []) do
        server = lookup_server_name(req)
        req_key = calc_req_key(req)

        Spoxy.Prerender.Server.perform(server, __MODULE__, req, req_key, @perform_default_timeout)
      end

      def sample_task_interval do
        Spoxy.Prerender.Server.sample_task_interval()
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
      def total_partitions() do
        @total_partitions
      end

      @doc """
      used for testing
      """
      def get_partition_state(partition) do
        server = partition_server(partition)
        Spoxy.Prerender.Server.get_partition_state(server)
      end

      def req_partition(req) do
        req_key = calc_req_key(req)
        calc_req_partition(req_key)
      end

      def inspect_all_partitions() do
        Enum.reduce(1..@total_partitions, %{total_listeners: 0, total_passive: 0}, fn partition,
                                                                                      acc ->
          %{total_listeners: partition_total, total_passive: partition_passive} =
            inspect_partition(partition)

          %{total_listeners: total_listeners, total_passive: total_passive} = acc

          new_total_listeners = total_listeners + partition_total
          new_total_passive = total_passive + partition_passive

          %{acc | total_listeners: new_total_listeners, total_passive: new_total_passive}
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

          new_total_listeners = total_listeners + Enum.count(listeners)
          new_total_passive = total_passive + Enum.count(passive)

          %{acc | total_listeners: new_total_listeners, total_passive: new_total_passive}
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
