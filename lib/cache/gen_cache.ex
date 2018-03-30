defmodule GenSpoxy.Cache do
  @moduledoc """
  This behaviour is responsible for implementing a caching layer on top of the query
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias Spoxy.Cache
      alias GenSpoxy.Stores.Ets

      @behaviour Spoxy.Cache.Behaviour

      @store_module Keyword.get(opts, :store_module, Ets)
      @query_module Keyword.get(opts, :query_module)

      cache_module = __MODULE__
      tasks_executor_mod = String.to_atom("#{cache_module}.TasksExecutor")

      @tasks_executor_mod tasks_executor_mod

      config = Keyword.get(opts, :config, [])
      executor_opts = Keyword.merge(config, cache_module: __MODULE__)

      defmodule @tasks_executor_mod do
        use GenSpoxy.Query.PeriodicTasksExecutor, executor_opts
      end

      tasks_executor_sup_mod = String.to_atom("#{tasks_executor_mod}.Supervisor")

      defmodule tasks_executor_sup_mod do
        use GenSpoxy.Query.Supervisor, supervised_module: tasks_executor_mod
      end

      def async_get_or_fetch(req, opts \\ []) do
        req_key = calc_req_key(req)
        mods = {@query_module, @store_module, @tasks_executor_mod}

        Cache.async_get_or_fetch(mods, req, req_key, opts)
      end

      def get_or_fetch(req, opts \\ []) do
        req_key = calc_req_key(req)
        mods = {@query_module, @store_module, @tasks_executor_mod}

        Cache.get_or_fetch(mods, req, req_key, opts)
      end

      @doc """
      receives a request `req`, determines it's signature (a.k.a `req_key`),
      then it fetches the local cache. it returns `nil` in case there is nothing in cache,
      else returns the cached entry
      """
      def get(req, opts \\ []) do
        req_key = calc_req_key(req)
        Cache.get(@store_module, req_key, opts)
      end

      def refresh_req!(req, opts) do
        req_key = calc_req_key(req)
        mods = {@query_module, @store_module}
        Cache.refresh_req!(mods, req, req_key, opts)
      end

      def await(task) do
        {:ok, resp, total} = Task.await(task)
      end

      @impl true
      def should_invalidate?(req, resp, metadata) do
        Cache.should_invalidate?(req, resp, metadata)
      end

      # defoverridable [should_invalidate?: 3]

      defp calc_req_key(req) do
        apply(@query_module, :calc_req_key, [req])
      end
    end
  end
end
