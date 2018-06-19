defmodule Neoscan.Transactions do
  @moduledoc false

  @moduledoc """
  The boundary for the Transactions system.
  """

  import Ecto.Query, warn: false
  alias Neoscan.Repo
  alias Neoscan.Vout
  alias Neoscan.Vin
  alias Neoscan.Transaction

  @doc """
  Returns the list of transactions in the home page.

  ## Examples

      iex> home_transactions()
      [%Transaction{}, ...]

  """
  def home_transactions do
    transaction_query =
      from(
        e in Transaction,
        order_by: [
          desc: e.block_time
        ],
        where: e.type != "miner_transaction",
        limit: 15,
        preload: [:vouts]
      )

    Repo.all(transaction_query)
  end

  @doc """
  Gets a single transaction by its hash value
  ## Examples
      iex> get_block_by_hash(123)
      %Block{}
      iex> get_block_by_hash(456)
      nil
  """
  def get_transaction_by_hash(hash) do
    query = from(t in Transaction, where: t.hash == ^hash)
    Repo.one(query)
  end

  @doc """
  Gets a single transaction by its hash and send it as a map
  ## Examples
      iex> get_block_by_hash_for_view(123)
      %{}
      iex> get_block_by_hash_for_view(456)
      nil
  """
  def get_transaction_by_hash_for_view(hash) do
    vout_query =
      from(
        v in Vout,
        order_by: [
          asc: v.n
        ]
      )

    query =
      from(
        e in Transaction,
        where: e.hash == ^hash,
        preload: [
          {:vouts, ^vout_query},
          :vins,
          :claims,
          :transfers
        ],
        select: e
      )

    Repo.one(query)
  end

  @doc """
  Returns the list of paginated transactions.
  ## Examples
      iex> paginate_transactions(page)
      [%Transaction{}, ...]
  """
  def paginate_transactions(pag), do: paginate_transactions(pag, nil)

  def paginate_transactions(pag, _) do
    vout_query =
      from(
        v in Vout,
        order_by: [
          asc: v.n
        ]
      )

    vin_query =
      from(
        vin in Vin,
        join: vout in Vout,
        on: vin.vout_n == vout.n and vin.vout_transaction_hash == vout.transaction_hash,
        select: vout
      )

    transaction_query =
      from(
        t in Transaction,
        order_by: [
          desc: t.block_index
        ],
        preload: [{:vins, ^vin_query}, {:vouts, ^vout_query}, :transfers, :claims]
      )

    Repo.paginate(transaction_query, page: pag, page_size: 15)
  end
end
