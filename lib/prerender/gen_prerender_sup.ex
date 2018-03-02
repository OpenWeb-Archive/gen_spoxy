defmodule GenSpoxy.Prerender.Supervisor do
  @moduledoc """
  a prerender dedicated supervisor.
  the prerender supervised module is assumed to implement the `GenSpoxy.Partitionable` behaviour
  """

  defmacro __using__(opts) do
    quote do
      use Supervisor

      @supervised_module Keyword.get(unquote(opts), :supervised_module)

      def start_link(opts \\ []) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def init(_opts) do
        total_partitions = apply(@supervised_module, :total_partitions, [])

        children =
          Enum.map(1..total_partitions, fn partition ->
            child_name = calc_child_name(partition)

            worker(
              @supervised_module,
              [[name: child_name]],
              id: "#{@supervised_module}-#{partition}"
            )
          end)

        supervise(children, strategy: :one_for_one)
      end

      defp calc_child_name(partition) do
        apply(@supervised_module, :partition_server, [partition])
      end
    end
  end
end
