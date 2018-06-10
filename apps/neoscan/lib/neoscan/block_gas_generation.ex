defmodule Neoscan.BlockGasGeneration do
  @moduledoc false

  @generation_amount [8, 7, 6, 5, 4, 3, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  @generation_length 22
  @decrement_interval 2_000_000

  @doc """
  Calculate the amount of gas generated by a block
  """
  def get_amount_generate_in_block(nil), do: nil

  def get_amount_generate_in_block(0), do: Enum.at(@generation_amount, 0) * 1.0

  def get_amount_generate_in_block(index) do
    if Integer.floor_div(index - 1, @decrement_interval) > @generation_length do
      0.0
    else
      position = Integer.floor_div(index - 1, @decrement_interval)
      Enum.at(@generation_amount, position) * 1.0
    end
  end
end
