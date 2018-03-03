defmodule Macros.Tests do
  defmacro defprerender(name, opts \\ [], do_req: do_req) do
    quote do
      defmodule unquote(name) do
        use GenSpoxy.Prerender, unquote(opts)

        @impl true
        def do_req(req) do
          unquote(do_req).(req)
        end

        @impl true
        def calc_req_key(req) do
          Enum.join(req, "-")
        end
      end
    end
  end
end
