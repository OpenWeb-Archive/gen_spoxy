defmodule GenSpoxy.Constants do
  @moduledoc """
  gathers all the default settings
  """

  def total_partitions do
    System.schedulers_online() * 10
  end

  def cache_ttl_ms do
    5000
  end

  def prerender_timeout do
    1500
  end

  def prerender_sampling_interval do
    200
  end

  def periodic_tasks_executor_sampling_interval do
    1500
  end
end
