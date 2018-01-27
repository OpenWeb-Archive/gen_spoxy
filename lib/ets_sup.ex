defmodule GenSpoxy.Stores.Ets.Supervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children =
      Enum.map(1..GenSpoxy.Stores.Ets.total_partitions(), fn partition ->
        worker(GenSpoxy.Stores.Ets, [[partition: partition]], id: "ets-store-#{partition}")
      end)

    supervise(children, strategy: :one_for_one)
  end
end
