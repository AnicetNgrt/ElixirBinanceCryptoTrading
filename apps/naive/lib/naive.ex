defmodule Naive do
  @moduledoc """
  Documentation for `Naive`.
  """
  def send_event(%Streamer.Binance.TradeEvent{} = event) do
    # Update soon
    #GenServer.cast(:trader, {:event, event})
  end
end
