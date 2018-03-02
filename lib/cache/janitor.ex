defmodule Spoxy.Cache.Janitor do
  @moduledoc """
  responsible on garbage collecting stale data out of the cache store (for example: `ets`)
  """

  def schedule_janitor_work(store_module, table_name, req_key, metadata, janitor_time) do
    entry = {store_module, table_name, req_key, metadata}
    timeout = janitor_time + 5_000
    pid = spawn(__MODULE__, :do_janitor_work, [timeout])
    Process.send_after(pid, {:invalidate_if_stale!, entry}, janitor_time)
  end

  def do_janitor_work(timeout \\ 30_000) do
    timeout = if timeout <= 0, do: 30_000, else: timeout

    receive do
      {:invalidate_if_stale!, {store_module, table_name, req_key, version}} ->
        case lookup_req(store_module, table_name, req_key) do
          {_resp, %{version: ^version}} ->
            invalidate!(store_module, table_name, req_key)

          _ ->
            :ignore
        end

      _ ->
        Process.exit(self(), :error)
    after
      timeout -> Process.exit(self(), :timeout)
    end
  end

  defp lookup_req(store_module, table_name, req_key) do
    apply(store_module, :lookup_req, [table_name, req_key])
  end

  defp invalidate!(store_module, table_name, req_key) do
    apply(store_module, :invalidate!, [table_name, req_key])
  end
end
