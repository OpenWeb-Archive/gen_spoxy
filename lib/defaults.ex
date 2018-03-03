defmodule GenSpoxy.Defaults do
  @moduledoc """
  gathers all the default settings
  """

  def total_partitions do
    System.schedulers_online() * 4
  end

  def prerender_timeout do
    5000
  end

  def prerender_sampling_interval do
    500
  end

  # for background tasks
  def periodic_sampling_interval do
    4000
  end
end
