defmodule Spoxy.Query.Behaviour do
  @moduledoc """
  executing the request itself
  """
  @callback do_req(req :: any) :: {:ok, any} | {:error, any}

  @doc """
  calculating the request signature (must be a deterministic calculation)
  i.e: given a `req` input, always returns the same `req_key`
  """
  @callback calc_req_key(req :: any) :: String.t()
end
