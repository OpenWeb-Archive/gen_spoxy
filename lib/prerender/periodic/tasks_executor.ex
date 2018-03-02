defmodule GenSpoxy.Prerender.PeriodicTasksExecutor do
  defmacro __using__(opts) do
    quote do
      use GenSpoxy.Periodic.TasksExecutor, unquote(opts)

      @cache_module Keyword.get(unquote(opts), :cache_module)

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
