defmodule GenSpoxy.Stores.Ets do
  use GenServer
  use GenSpoxy.Partitionable

  @behaviour GenSpoxy.Store

  @total_partitions GenSpoxy.Constants.total_partitions(:ets)

  @moduledoc """
  `EtsCacheStore' implements the `GenSpoxy.Store` behaviour.
  It stores its data under `ets` and it manages it in using sharded `GenServer`.
  """

  # API
  def start_link(opts \\ []) do
    {:ok, partition} = Keyword.fetch(opts, :partition)

    opts = Keyword.put(opts, :name, partition_server(partition))

    GenServer.start_link(__MODULE__, partition, opts)
  end

  @impl true
  def lookup_req(table_name, req_key) do
    partition = calc_req_partition(table_name)

    case :ets.lookup(ets_partition_table(partition), req_key) do
      [{^req_key, {resp, metadata}}] -> {resp, metadata}
      _ -> nil
    end
  end

  @impl true
  def store_req!(table_name, {req, req_key, resp, metadata}, opts) do
    partition = calc_req_partition(table_name)

    GenServer.call(
      partition_server(partition),
      {:store_req!, partition, req, req_key, resp, metadata, opts}
    )
  end

  @impl true
  def invalidate!(table_name, req_key) do
    partition = calc_req_partition(table_name)
    server = partition_server(partition)

    GenServer.call(server, {:invalidate!, partition, req_key})
  end

  @doc """
  used for testing
  """
  def reset_partition!(partition) do
    GenServer.call(partition_server(partition), {:reset!, partition})
  end

  @doc """
  used for testing
  """
  def reset_all! do
    tasks =
      Enum.map(1..@total_partitions, fn partition ->
        Task.async(fn -> reset_partition!(partition) end)
      end)

    Enum.each(tasks, &Task.await/1)
  end

  # callbacks
  @impl true
  def init(partition) do
    :ets.new(ets_partition_table(partition), [
      :set,
      :protected,
      :named_table,
      {:read_concurrency, true}
    ])

    {:ok, []}
  end

  @impl true
  def handle_call({:store_req!, partition, _req, req_key, resp, metadata, opts}, _from, state) do
    uuid = UUID.uuid1()
    now = System.system_time(:milliseconds)

    {:ok, ttl_ms} = Keyword.fetch(opts, :ttl_ms)
    expires_at = now + ttl_ms

    metadata = Map.merge(metadata, %{uuid: uuid, expires_at: expires_at})

    :ets.insert(ets_partition_table(partition), {req_key, {resp, metadata}})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:invalidate!, partition, req_key}, _from, state) do
    :ets.delete(ets_partition_table(partition), req_key)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:reset!, partition}, _from, state) do
    :ets.delete_all_objects(ets_partition_table(partition))

    {:reply, :ok, state}
  end

  @impl true
  def total_partitions do
    @total_partitions
  end

  @impl true
  def calc_req_partition(table_name) do
    1 + :erlang.phash2(table_name, @total_partitions)
  end

  defp ets_partition_table(partition) do
    String.to_atom("ets-#{partition}")
  end
end
