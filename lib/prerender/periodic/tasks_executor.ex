defmodule GenSpoxy.Prerender.PeriodicTasksExecutor do
  @moduledoc """
  responsible on periodically executing prerender tasks.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use GenSpoxy.Periodic.TasksExecutor, opts

      @cache_module Keyword.get(opts, :cache_module)

      def execute_tasks!(_req_key, req_tasks) do
        Enum.each(req_tasks, fn [req, opts] ->
          Task.start(fn ->
            apply(@cache_module, :refresh_req!, [req, opts])
          end)
        end)

        :ok
      end
    end
  end
end
