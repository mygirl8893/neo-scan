defmodule Neoscan.Transactions do
  @moduledoc false

  @moduledoc """
  The boundary for the Transactions system.
  """

  @page_size 15
  @neo_asset_hash <<197, 111, 51, 252, 110, 207, 205, 12, 34, 92, 74, 179, 86, 254, 229, 147, 144,
                    175, 133, 96, 190, 14, 147, 15, 174, 190, 116, 166, 218, 255, 124, 155>>

  import Ecto.Query, warn: false
  alias Neoscan.Repo
  alias Neoscan.Asset
  alias Neoscan.Vout
  alias Neoscan.Vin
  alias Neoscan.Claim
  alias Neoscan.Transaction
  alias Neoscan.Transfer
  alias Neoscan.AddressTransaction

  @doc """
  Gets a single transaction by its hash and send it as a map
  ## Examples
      iex> get(123)
      %{}
      iex> get(456)
      nil
  """
  def get(hash) do
    query =
      from(
        e in Transaction,
        where: e.hash == ^hash,
        preload: [
          {:transfers, ^transfer_query()},
          :asset
        ],
        select: e
      )

    add_extra(Repo.one(query))
  end

  @doc """
  Returns the list of paginated transactions.
  ## Examples
      iex> paginate(page)
      [%Transaction{}, ...]
  """
  def paginate(page) do
    transaction_query =
      from(
        t in Transaction,
        order_by: [
          desc: t.block_index
        ],
        preload: [
          {:transfers, ^transfer_query()},
          :asset
        ],
        where: t.type != "miner_transaction"
      )

    # override total entries to avoid counting the whole set
    result =
      Repo.paginate(
        transaction_query,
        page: page,
        page_size: @page_size,
        options: [total_entries: 10_000]
      )

    %{result | entries: Enum.map(result.entries, &add_extra/1)}
  end

  def get_for_block(block_hash, page) do
    transaction_query =
      from(
        t in Transaction,
        where: t.block_hash == ^block_hash,
        preload: [{:transfers, ^transfer_query()}, :asset],
        order_by: t.block_time,
        select: t,
        limit: @page_size
      )

    result = Repo.paginate(transaction_query, page: page, page_size: @page_size)
    %{result | entries: Enum.map(result.entries, &add_extra/1)}
  end

  def get_for_address(address_hash, page) do
    transaction_query =
      from(
        t in Transaction,
        join: at in AddressTransaction,
        on: at.transaction_hash == t.hash,
        where: at.address_hash == ^address_hash,
        preload: [{:transfers, ^transfer_query()}, :asset],
        order_by: [desc: at.block_time],
        select: t
      )

    result =
      Repo.paginate(
        transaction_query,
        page: page,
        page_size: @page_size,
        options: [total_entries: 10_000]
      )

    %{result | entries: Enum.map(result.entries, &add_extra/1)}
  end

  defp add_extra(nil), do: nil

  defp add_extra(transaction) do
    vouts =
      Repo.all(
        from(
          v in Vout,
          order_by: [asc: v.n],
          where: v.transaction_hash == ^transaction.hash,
          preload: [:asset]
        )
      )

    vins =
      Repo.all(
        from(
          v in Vout,
          join: vin in Vin,
          on: vin.vout_n == v.n and vin.vout_transaction_hash == v.transaction_hash,
          where: vin.transaction_hash == ^transaction.hash,
          preload: [:asset]
        )
      )

    claims =
      Repo.all(
        from(
          v in Vout,
          join: claim in Claim,
          on: claim.vout_n == v.n and claim.vout_transaction_hash == v.transaction_hash,
          where: claim.transaction_hash == ^transaction.hash,
          preload: [:asset]
        )
      )

    vouts = Enum.map(vouts, &Asset.update_struct/1)
    vins = Enum.map(vins, &Asset.update_struct/1)
    claims = Enum.map(claims, &Asset.update_struct/1)
    transfers = Enum.map(transaction.transfers, &Asset.update_struct/1)
    asset = Asset.update_name(transaction.asset)

    transaction
    |> Map.put(:vins, vins)
    |> Map.put(:vouts, vouts)
    |> Map.put(:claims, claims)
    |> Map.put(:transfers, transfers)
    |> Map.put(:asset, asset)
  end

  defp transfer_query do
    from(
      transfer in Transfer,
      preload: [:asset]
    )
  end

  def get_claimed_vouts(address_hash) do
    result =
      Repo.all(
        from(
          vout in Vout,
          join: claim in Claim,
          on: claim.vout_n == vout.n and claim.vout_transaction_hash == vout.transaction_hash,
          where: vout.address_hash == ^address_hash,
          select: {vout, claim},
          preload: [:asset]
        )
      )

    Enum.map(result, fn {vout, claim} -> {Asset.update_struct(vout), claim} end)
  end

  def get_unspent_vouts(address_hash) do
    result =
      Repo.all(
        from(
          vout in Vout,
          where: vout.address_hash == ^address_hash and vout.spent == false,
          preload: [:asset]
        )
      )

    Enum.map(result, &Asset.update_struct/1)
  end

  def get_claimable_vouts(address_hash) do
    result =
      Repo.all(
        from(
          vout in Vout,
          where:
            vout.address_hash == ^address_hash and vout.spent == true and vout.claimed == false and
              vout.asset_hash == ^@neo_asset_hash,
          preload: [:asset]
        )
      )

    Enum.map(result, &Asset.update_struct/1)
  end

  def get_unclaimed_vouts(address_hash) do
    result =
      Repo.all(
        from(
          vout in Vout,
          where:
            vout.address_hash == ^address_hash and vout.claimed == false and
              vout.asset_hash == ^@neo_asset_hash,
          preload: [:asset]
        )
      )

    Enum.map(result, &Asset.update_struct/1)
  end
end
