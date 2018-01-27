defmodule GenSpoxy.Prerender.Supervisor do
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
            child_name = apply(@supervised_module, :partition_server, [partition])

            worker(
              @supervised_module,
              [[name: child_name]],
              id: "#{@supervised_module}-#{partition}"
            )
          end)

        supervise(children, strategy: :one_for_one)
      end
    end
  end
end
