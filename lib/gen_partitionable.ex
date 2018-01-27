defmodule GenSpoxy.Partitionable do
  @callback total_partitions() :: Integer

  @callback calc_req_partition(key :: String.t()) :: term

  @callback partition_server(key :: term) :: any

  defmacro __using__(_opts) do
    quote do
      @behaviour GenSpoxy.Partitionable

      def partition_server(partition) do
        {:global, "#{__MODULE__}-#{partition}"}
      end

      defoverridable partition_server: 1
    end
  end
end
