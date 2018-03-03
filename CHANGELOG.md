## Changelog

## v0.0.14-beta.1
* renaming `Constants` to `Defaults`
* changing the defaults to suit most applications out-of-the-box
* `GenSpoxy.Cache` and `GenSpoxy.Prerender` expect configuations override under `config`

for example:
```elixir
  defmodule SamplePrerender do
    use GenSpoxy.Prerender,
        config: [prerender_timeout: 3000]

    @impl true
    def do_req(req) do
      # slow calculation of `req`
    end

    @impl true
    def calc_req_key(req) do
      Enum.join(req, "-")
    end
  end

  defmodule SampleCache do
    use GenSpoxy.Cache,
      store_module: Ets,
      prerender_module: SamplePrerender,
      config: [periodic_sampling_interval: 100]
  end
```

* `GenSpoxy.Prerender` settings are:
  * `prerender_timeout`           (defaults to `Defaults.prerender_timeout()`)
  * `prerender_total_partitions`  (defaults to `Defaults.total_partitions()`)
  * `prerender_sampling_interval` (defaults to `Defaults.prerender_sampling_interval()`)

* `GenSpoxy.Cache` settings for its underlying `TasksExecutor` are:
  * `periodic_sampling_interval`  (defaults to `Defaults.periodic_sampling_interval()`)
  * `periodic_total_partitions    (defaults to `Defaults.total_partitions()`)


## v0.0.12
first release
