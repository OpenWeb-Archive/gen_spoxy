# GenSpoxy

the `GenSpoxy` package consist of battle-tested abstractions that help creating in-memory caching


```elixir
defmodule SampleCache do
  use GenSpoxy.Cache, prerender_module: SamplePrerender
end

defmodule SamplePrerender do
  use GenSpoxy.Prerender

  @impl true
  def do_req(req) do
    # slow calculation of `req`
  end

  @impl true
  def calc_req_key(req) do
    Enum.join(req, "-")
  end
end

# usage
req = ["fetch data", "https://www.very-slow-server.com"]
SampleCach.get_or_fetch(req)  # blocking manner

SampleCach.async_get_or_fetch(req)  # async manner
```
