defmodule Spoxy.Cache.Behaviour do
  @moduledoc """
  decides if the stored data should be invalidated (for example stale data)
  """
  @callback should_invalidate?(req :: any, resp :: any, metadata :: any) :: boolean()
end
