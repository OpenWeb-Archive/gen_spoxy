defmodule GenSpoxy.Cache do
  @moduledoc """
  This behaviour is responsible for implementing a caching layer on top of the prerender
  """

  defmacro __using__(opts) do
    quote do
      require Logger

      @behaviour Spoxy.Cache.Behaviour

      @store_module Keyword.get(unquote(opts), :store_module, GenSpoxy.Stores.Ets)
      @prerender_module Keyword.get(unquote(opts), :prerender_module)

      cache_module = __MODULE__
      tasks_executor_mod = String.to_atom("#{cache_module}TasksExecutor")

      @tasks_executor_mod tasks_executor_mod
      defmodule @tasks_executor_mod do
        use GenSpoxy.Prerender.PeriodicTasksExecutor, cache_module: cache_module
      end

      tasks_executor_sup_mod = String.to_atom("#{tasks_executor_mod}.Supervisor")
      defmodule tasks_executor_sup_mod do
        use GenSpoxy.Prerender.Supervisor, supervised_module: tasks_executor_mod
      end

      def async_get_or_fetch(req, opts \\ []) do
        req_key = calc_req_key(req)

        Spoxy.Cache.async_get_or_fetch(
          {@prerender_module, @store_module, @tasks_executor_mod},
          req,
          req_key,
          opts
        )
      end

      def get_or_fetch(req, opts \\ []) do
        req_key = calc_req_key(req)

        Spoxy.Cache.get_or_fetch(
          {@prerender_module, @store_module, @tasks_executor_mod},
          req,
          req_key,
          opts
        )
      end

      @doc """
      receives a request `req`, determines it's signature (a.k.a `req_key`),
      then it fetches the local cache. it returns `nil` in case there is nothing in cache,
      else returns the cached entry
      """
      def get(req, opts \\ []) do
        req_key = calc_req_key(req)
        Spoxy.Cache.get(@store_module, req_key, opts)
      end

      def refresh_req!(req, opts) do
        req_key = calc_req_key(req)
        Spoxy.Cache.refresh_req!({@prerender_module, @store_module}, req, req_key, opts)
      end

      def await(task) do
        {:ok, resp, total} = Task.await(task)
      end

      def do_req(req) do
        Spoxy.Cache.do_req(@prerender_module, req)
      end

      def store_req!(opts) do
        Spoxy.Cache.store_req!(@store_module, opts)
      end

      def lookup_req(table_name, req_key) do
        Spoxy.Cache.lookup_req(@store_module, table_name, req_key)
      end

      @impl true
      def should_invalidate?(req, resp, metadata) do
        Spoxy.Cache.should_invalidate?(req, resp, metadata)
      end

      # defoverridable [should_invalidate?: 3]

      defp calc_req_key(req) do
        apply(@prerender_module, :calc_req_key, [req])
      end
    end
  end
end
