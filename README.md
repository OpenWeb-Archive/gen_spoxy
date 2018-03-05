# GenSpoxy

the `GenSpoxy` package consist of battle-tested abstractions that help creating in-memory caching

### Advantages of `GenSpoxy`:
1. Makes it very easy to create from scratch highly-concurrent applicative reverse-proxy
that holds an internal short-lived (configurable) cache.
1. CDN like Origin Shielding - when multiple clients ask for the same request and experience a cache miss,
the calculation will be done only once
1. Supports non-blocking mode for requests that are willing to receive stale cached data
1. Eases the time-to-market of features that require some caching

### notes:
1. The default cache storage used is `ETS`
1. The default behaviour is `non-blocking`
1. Each request should be transformed to a signature deterministically (a.k.a. `req_key`)


### usage example:
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
opts = [
  table_name: "sample-table",
  do_janitor_work: true, # whether we garbage collect expired data
  ttl_ms: 5_000 # the data is considered non-stale for 5 seconds
]

# `req` is application dependant
req = %{url: "https://www.very-slow-server.com", platform: "mobile"}

SampleCache.get_or_fetch(req, opts)  # blocking manner

SampleCache.async_get_or_fetch(req, opts)  # async manner (we're OK with accepting a stale response)
```
