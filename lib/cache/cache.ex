defmodule Spoxy.Cache do
  @moduledoc """
  """

  alias Spoxy.Cache.Janitor

  def async_get_or_fetch(mods, req, req_key, opts \\ []) do
    Task.async(fn ->
      started = System.system_time(:milliseconds)

      {:ok, resp} = get_or_fetch(mods, req, req_key, opts)

      ended = System.system_time(:milliseconds)

      {:ok, resp, ended - started}
    end)
  end

  def get_or_fetch(mods, req, req_key, opts \\ []) do
    {prerender_module, store_module, tasks_executor_mod} = mods

    hit_or_miss = get(store_module, req_key, opts)

    case hit_or_miss do
      {:hit, {resp, metadata}} ->
        if should_invalidate?(req, resp, metadata) do
          # the cache holds stale data,
          # now we need to decide if we will force refreshing the cache
          # before returning a response (a _blocking_ call)
          # or whether we'll return a stale reponse and enqueue
          # a background task that will refresh the cache
          blocking = Keyword.get(opts, :blocking, false)

          if blocking do
            # we don't want the stale data, so force recalculation
            refresh_req!({prerender_module, store_module}, req, req_key, opts)
          else
            # we'll spawn a background task in a fire-and-forget manner
            # that will make sure the stale data is refreshed
            # so that future requests, will benefit from a fresh data
            Task.start(fn ->
              enqueue_req(tasks_executor_mod, req_key, req, opts)
            end)

            # returning the stale data
            {:ok, resp}
          end
        else
          # we have a fresh data in the cache
          {:ok, resp}
        end

      {:miss, _} ->
        # we have nothing in the cache, we need to calculate the request's value
        refresh_req!({prerender_module, store_module}, req, req_key, opts)
    end
  end

  def get(store_module, req_key, opts \\ []) do
    {:ok, table_name} = Keyword.fetch(opts, :table_name)
    lookup = lookup_req(store_module, table_name, req_key)

    case lookup do
      nil -> {:miss, "couldn't locate in cache"}
      _ -> {:hit, lookup}
    end
  end

  def refresh_req!({prerender_module, store_module}, req, req_key, opts) do
    case do_req(prerender_module, req) do
      {{:ok, resp}, :active} ->
        {:ok, table_name} = Keyword.fetch(opts, :table_name)
        {:ok, ttl_ms} = Keyword.fetch(opts, :ttl_ms)

        version = UUID.uuid1()
        metadata = %{version: version}

        store_opts = [table_name, {req, req_key, resp, metadata}, opts]
        store_req!(store_module, store_opts)

        do_janitor_work = Keyword.get(opts, :do_janitor_work, true)

        if do_janitor_work do
          Janitor.schedule_janitor_work(
            store_module,
            table_name,
            req_key,
            version,
            ttl_ms * 2
          )
        end

        {:ok, resp}

      {{:ok, resp}, :passive} ->
        {:ok, resp}

      {{:error, reason}, _} ->
        {:error, reason}
    end
  end

  def do_req(prerender_module, req) do
    apply(prerender_module, :perform, [req])
  end

  def store_req!(store_module, opts) do
    apply(store_module, :store_req!, opts)
  end

  def lookup_req(store_module, table_name, req_key) do
    apply(store_module, :lookup_req, [table_name, req_key])
  end

  def should_invalidate?(_req, _resp, metadata) do
    %{expires_at: expires_at} = metadata

    System.system_time(:milliseconds) > expires_at
  end

  def enqueue_req(tasks_executor_mod, req_key, req, opts) do
    tasks_executor_mod.enqueue_task(req_key, [req, opts])
  end
end
