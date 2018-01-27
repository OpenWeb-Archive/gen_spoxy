defmodule GenSpoxy.PrerenderStore do
  @moduledoc """
  Behaviour to be implemented by backing stores to be used in for `GenPrerenderCache`
  """

  @doc """
  retrieving the data locally
  """
  @callback lookup_req(table_name :: term, req_key :: any) :: any

  @doc """
  storing the prerender 'request' -> 'response' pairs locally
  """
  @callback store_req!(
              table_name :: term,
              req :: any,
              req_key :: any,
              resp :: any,
              metadata :: any,
              opts :: any
            ) :: any

  @doc """
  removing the cached 'request' -> 'response' pair using `req_key`
  """
  @callback invalidate!(table_name :: term, req_key :: any) :: any
end
