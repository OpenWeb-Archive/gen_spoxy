defmodule GenSpoxy.Prerender.PeriodicTasksExecutor do
  @moduledoc """
  responsible on periodically executing prerender tasks.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use GenSpoxy.Periodic.TasksExecutor, opts

      @cache_module Keyword.get(opts, :cache_module)

      def execute_tasks!(_req_key, []), do: :ok

      def execute_tasks!(req_key, [task | _] = _req_tasks) do
        [req, opts] = task

        # since all `_req_tasks` are exactly the same (since all have the same `req_key`)
        # we execute only one task

        apply(@cache_module, :refresh_req!, [req, opts])

        :ok
      end
    end
  end
end
