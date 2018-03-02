defmodule GenSpoxy.PrerenderCache do
  @moduledoc """
  This behaviour is responsible for implementing a caching layer on top of the prerender
  """

  @doc """
  decides if the stored data should be invalidated (for example stale data)
  """
  @callback should_invalidate?(req :: any, resp :: any, metadata :: any) :: boolean()

  defmacro __using__(opts) do
    quote do
      require Logger

      @behaviour GenSpoxy.PrerenderCache

      @store_module Keyword.get(unquote(opts), :store_module, GenSpoxy.Stores.Ets)
      @prerender_module Keyword.get(unquote(opts), :prerender_module)

      cache_mod = __MODULE__
      tasks_executor_mod = String.to_atom("#{cache_mod}TasksExecutor")

      @tasks_executor_mod tasks_executor_mod
      defmodule @tasks_executor_mod do
        use GenSpoxy.PeriodicPrerenderTasksExecutor, cache_module: cache_mod
      end

      defmodule String.to_atom("#{tasks_executor_mod}.Supervisor") do
        use GenSpoxy.Prerender.Supervisor, supervised_module: tasks_executor_mod
      end

      def async_get_or_fetch(req, opts \\ []) do
        Task.async(fn ->
          started = System.system_time(:milliseconds)

          {:ok, resp} = get_or_fetch(req, opts)

          ended = System.system_time(:milliseconds)

          {:ok, resp, ended - started}
        end)
      end

      def await(task) do
        {:ok, resp, total} = Task.await(task)
      end

      def get_or_fetch(req, opts \\ []) do
        {:ok, table_name} = Keyword.fetch(opts, :table_name)

        req_key = calc_req_key(req)
        hit_or_miss = get(req, opts)

        case hit_or_miss do
          {:hit, {resp, metadata}} ->
            if should_invalidate?(req, resp, metadata) do
              # the cache holds stale data,
              # now we need to decide if we will force refreshing the cache
              # before returning a response (a _blocking_ call) or if whether we'll return
              # a stale reponse and enqueue a background task that will refresh the cache
              blocking = Keyword.get(opts, :blocking, false)

              if blocking do
                # we don't want the stale data, so force recalculation
                refresh_req!(req, opts)
              else
                # we'll spawn a background task in a fire-and-forget manner
                # that will make sure the stale data is refreshed so that future requests
                # will benefit from a fresh data
                Task.start(fn ->
                  enqueue_req(req_key, req, opts)
                end)

                # returning the stale data
                {:ok, resp}
              end
            else
              # we have fresh data
              {:ok, resp}
            end

          {:miss, _} ->
            # we have nothing in the cache, we need to calculate the request's value
            refresh_req!(req, opts)
        end
      end

      @doc """
      receives a request `req`, determines it's signature (a.k.a `req_key`),
      then it fetches the local cache. it returns `nil` in case there is nothing in cache,
      else returns the cached entry
      """
      def get(req, opts \\ []) do
        req_key = calc_req_key(req)

        {:ok, table_name} = Keyword.fetch(opts, :table_name)
        lookup = lookup_req(table_name, req_key)

        case lookup do
          nil -> {:miss, "couldn't locate in cache"}
          {resp, metadata} -> {:hit, lookup}
        end
      end

      def refresh_req!(req, opts) do
        req_key = calc_req_key(req)

        case do_req(req) do
          {{:ok, resp}, :active} ->
            {:ok, table_name} = Keyword.fetch(opts, :table_name)
            {:ok, ttl_ms} = Keyword.fetch(opts, :ttl_ms)

            version = UUID.uuid1()
            metadata = %{version: version}

            store_req!([table_name, req, req_key, resp, metadata, opts])

            do_janitor_work = Keyword.get(opts, :do_janitor_work, true)

            if do_janitor_work do
              Spoxy.StoreJanitor.schedule_janitor_work(
                @store_module,
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

      def enqueue_req(req_key, req, opts) do
        @tasks_executor_mod.enqueue_task(req_key, [req, opts])
      end

      defoverridable enqueue_req: 3

      def do_req(req) do
        apply(@prerender_module, :perform, [req])
      end

      def store_req!(opts) do
        apply(@store_module, :store_req!, opts)
      end

      def lookup_req(table_name, req_key) do
        apply(@store_module, :lookup_req, [table_name, req_key])
      end

      @impl true
      def should_invalidate?(req, resp, metadata) do
        %{expires_at: expires_at} = metadata

        System.system_time(:milliseconds) > expires_at
      end

      defoverridable should_invalidate?: 3

      defp calc_req_key(req) do
        apply(@prerender_module, :calc_req_key, [req])
      end
    end
  end
end
