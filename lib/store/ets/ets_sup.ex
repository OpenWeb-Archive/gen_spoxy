defmodule GenSpoxy.Stores.Ets.Supervisor do
  @moduledoc """
  supervising the `ets` tables used as a cache store
  """

  use Supervisor

  alias GenSpoxy.Stores.Ets

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children =
      Enum.map(1..Ets.total_partitions(), fn partition ->
        worker(Ets, [[partition: partition]], id: "ets-store-#{partition}")
      end)

    supervise(children, strategy: :one_for_one)
  end
end
