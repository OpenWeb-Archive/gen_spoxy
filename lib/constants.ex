defmodule GenSpoxy.Constants do
  require Logger

  def total_partitions(_ctx) do
    System.schedulers_online() * 3
  end

  def default_cache_ttl_ms do
    5000
  end

  def default_prerender_timeout do
    1500
  end

  def default_prerender_sampling_interval do
    200
  end

  def default_periodic_tasks_executor_sampling_interval do
    4000
  end
end
