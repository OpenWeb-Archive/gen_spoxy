defmodule GenSpoxy.Store do
  @moduledoc """
  Behaviour to be implemented by backing stores
  """

  @doc """
  retrieving the data locally
  """
  @callback lookup_req(table_name :: term, req_key :: any) :: any

  @doc """
  storing the prerender 'request' -> 'response' pairs locally
  """
  @callback store_req!(
              table_name :: String.t(),
              entry :: tuple,
              opts :: any
            ) :: any

  @doc """
  removing the cached 'request' -> 'response' pair using `req_key`
  """
  @callback invalidate!(table_name :: String.t(), req_key :: any) :: any
end
