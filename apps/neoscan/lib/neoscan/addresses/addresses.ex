defmodule Neoscan.Addresses do
  @moduledoc """
  The boundary for the Addresses system.
  """

  @neo_asset_hash <<197, 111, 51, 252, 110, 207, 205, 12, 34, 92, 74, 179, 86, 254, 229, 147, 144,
                    175, 133, 96, 190, 14, 147, 15, 174, 190, 116, 166, 218, 255, 124, 155>>

  @gas_asset_hash <<96, 44, 121, 113, 139, 22, 228, 66, 222, 88, 119, 142, 20, 141, 11, 16, 132,
                    227, 178, 223, 253, 93, 230, 183, 177, 108, 238, 121, 105, 40, 45, 231>>

  @page_size 15
  @balance_history_size 500

  @day_seconds 86_400

  import Ecto.Query, warn: false

  require Logger

  alias Neoscan.Repo
  alias Neoscan.Address
  alias Neoscan.AddressBalance
  alias Neoscan.AddressTransactionBalance
  alias Neoscan.Asset

  @doc """
  Gets a single address by its hash and send it as a map
  ## Examples
      iex> get(123)
      %{}
      iex> get(456)
      nil
  """
  def get(hash) do
    query = from(e in Address, where: e.hash == ^hash)
    Repo.one(query)
  end

  def get_balances(hash) do
    result =
      Repo.all(
        from(
          ab in AddressBalance,
          join: a in Asset,
          on: ab.asset_hash == a.transaction_hash,
          where: ab.address_hash == ^hash,
          select: %{
            name: a.name,
            asset: ab.asset_hash,
            value: ab.value,
            precision: a.precision,
            type: a.type
          }
        )
      )

    Enum.map(result, &format_balance/1)
  end

  # todo remove
  defp format_balance(%{name: name, value: value, precision: precision, type: type} = balance) do
    %{balance | name: Asset.filter_name(name), value: Asset.compute_value(value, precision, type)}
  end

  def get_split_balance(nil), do: nil

  def get_split_balance(binary_hash) do
    balances = get_balances(binary_hash)
    neo_balance = Enum.find(balances, &(&1.asset == @neo_asset_hash))
    gas_balance = Enum.find(balances, &(&1.asset == @gas_asset_hash))

    token_balances =
      Enum.filter(balances, &(not (&1.asset in [@neo_asset_hash, @gas_asset_hash])))

    %{
      neo: if(is_nil(neo_balance), do: 0, else: neo_balance.value),
      gas: if(is_nil(gas_balance), do: 0.0, else: gas_balance.value),
      tokens: token_balances
    }
  end

  @doc """
  Returns the list of paginated addresses.
  ## Examples
      iex> paginate(page)
      [%Address{}, ...]
  """
  def paginate(page) do
    addresses_query =
      from(
        e in Address,
        order_by: [
          desc: e.last_transaction_time
        ],
        limit: @page_size
      )

    Repo.paginate(addresses_query, page: page, page_size: @page_size)
  end

  def get_balance_history(hash) do
    balances = get_balances(hash)

    balances =
      Enum.reduce(balances, %{}, fn %{value: value, name: name}, acc ->
        Map.put(acc, name, value)
      end)

    address_history =
      Repo.all(
        from(
          atb in AddressTransactionBalance,
          where: atb.address_hash == ^hash,
          order_by: [desc: atb.block_time],
          preload: [:asset],
          limit: @balance_history_size
        )
      )

    empty_days =
      Enum.map(
        0..30,
        &%{block_time: DateTime.to_unix(DateTime.utc_now()) - &1 * @day_seconds, asset: nil}
      )

    address_history =
      Enum.map(address_history, &%{&1 | block_time: DateTime.to_unix(&1.block_time)}) ++
        empty_days

    address_history =
      address_history
      |> Enum.group_by(&(div(&1.block_time, @day_seconds) * @day_seconds))
      |> Enum.map(fn {time, balances} ->
        %{time: time, assets: reduce_balance_to_assets(balances)}
      end)

    address_history
    |> Enum.sort_by(& &1.time)
    |> Enum.reverse()
    |> reduce_address_history(balances, [])
    |> Enum.reverse()
    |> Enum.take(30)
    |> Enum.reverse()
  end

  defp reduce_address_history([], _, acc), do: acc

  defp reduce_address_history([%{assets: assets, time: time} | rest], balances, acc) do
    new_balances =
      Enum.reduce(assets, balances, fn {name, value}, acc ->
        Map.update!(acc, name, &(&1 - value))
      end)

    assets = Enum.map(balances, fn {key, value} -> %{key => value} end)
    reduce_address_history(rest, new_balances, [%{assets: assets, time: time} | acc])
  end

  defp reduce_balance_to_assets(balances) do
    balances
    |> Enum.filter(&(not is_nil(&1.asset)))
    |> Enum.map(&Asset.update_struct/1)
    |> Enum.map(&{&1.asset.name, &1.value})
    |> Enum.group_by(fn {asset_name, _} -> asset_name end, fn {_, value} -> value end)
    |> Enum.map(fn {asset_name, value_list} -> {asset_name, Enum.sum(value_list)} end)
    |> Enum.into(%{})
  end

  def get_transaction_abstracts_raw(address_hash, page) do
    transaction_query =
      from(
        atb in AddressTransactionBalance,
        where: atb.address_hash == ^address_hash,
        preload: [:transaction, :asset],
        order_by: [desc: atb.block_time]
      )

    result = Repo.paginate(transaction_query, page: page, page_size: @page_size)
    %{result | entries: Enum.map(result.entries, &Asset.update_struct/1)}
  end

  def get_transaction_abstracts(address_hash, page) do
    result = get_transaction_abstracts_raw(address_hash, page)
    %{result | entries: create_transaction_abstracts(result.entries)}
  end

  def get_address_to_address_abstracts(address_hash1, address_hash2, page) do
    transaction_query =
      from(
        atb in AddressTransactionBalance,
        join: atb2 in AddressTransactionBalance,
        on: atb.transaction_hash == atb2.transaction_hash and atb.asset_hash == atb2.asset_hash,
        where:
          atb.address_hash == ^address_hash1 and atb2.address_hash == ^address_hash2 and
            fragment("sign(?)", atb.value) != fragment("sign(?)", atb2.value),
        preload: [:asset, :transaction],
        order_by: [desc: atb.block_time]
      )

    result = Repo.paginate(transaction_query, page: page, page_size: @page_size)

    %{
      result
      | entries: create_transaction_abstracts(Enum.map(result.entries, &Asset.update_struct/1))
    }
  end

  defp get_related_transaction_abstracts(%{
         transaction_hash: transaction_hash,
         asset_hash: asset_hash,
         value: value
       }) do
    atbs_query =
      from(
        atb in AddressTransactionBalance,
        where: atb.transaction_hash == ^transaction_hash and atb.asset_hash == ^asset_hash,
        preload: [:asset]
      )

    atbs_query =
      if value < 0 do
        from(atb in atbs_query, where: atb.value > 0.0)
      else
        from(atb in atbs_query, where: atb.value < 0.0)
      end

    Enum.map(Repo.all(atbs_query), &Asset.update_struct/1)
  end

  defp create_transaction_abstracts(transactions) do
    transactions
    |> Enum.map(&Map.put(&1, :related, get_related_transaction_abstracts(&1)))
    |> Enum.map(&create_transaction_abstract/1)
  end

  defp create_transaction_abstract(abt) do
    {address_from, address_to} = get_transaction_abstract_actors(abt)

    %{
      transaction_hash: abt.transaction_hash,
      address_from: address_from,
      address_to: address_to,
      value: abs(abt.value),
      asset_hash: abt.asset_hash,
      block_time: abt.transaction.block_time,
      block_index: abt.transaction.block_index
    }
  end

  # self transfer for gas claim
  defp get_transaction_abstract_actors(%{value: 0.0, address_hash: address_hash}),
    do: {address_hash, address_hash}

  defp get_transaction_abstract_actors(abt) do
    is_sender = abt.value < 0
    original = abt.address_hash
    other = get_transaction_abstract_other_actor(abt)
    if is_sender, do: {original, other}, else: {other, original}
  end

  defp get_transaction_abstract_other_actor(%{asset_hash: @gas_asset_hash, related: []}),
    do: "claim"

  defp get_transaction_abstract_other_actor(%{related: []}), do: "mint"

  defp get_transaction_abstract_other_actor(%{related: [%{address_hash: address_hash}]}),
    do: address_hash

  defp get_transaction_abstract_other_actor(_), do: "multi"
end
