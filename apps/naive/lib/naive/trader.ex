defmodule Naive.Trader do
  use GenServer
  alias Streamer.Binance.TradeEvent
  alias Decimal, as: D

  defmodule State do
    @enforce_keys [:symbol, :profit_interval, :tick_size]
    defstruct [
      :symbol,
      :buy_order,
      :sell_order,
      :profit_interval,
      :tick_size
    ]
  end

  def start_link(%{} = args) do
    GenServer.start_link(__MODULE__, args, name: :trader)
  end

  def init(%{} = args) do
    tick_size = fetch_tick_size(args.symbol)

    {:ok,
     %State{
       symbol: args.symbol,
       profit_interval: args.profit_interval,
       tick_size: tick_size
     }}
  end

  # No order state
  def handle_cast(
        {:event, %TradeEvent{price: price}},
        %State{symbol: symbol, buy_order: nil} = state
      ) do
    quantity = 100

    # https://www.binance.com/au/support/articles/360033779452-Types-of-Order
    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_buy(
        symbol,
        quantity,
        price,
        "GTC"
      )

    {:noreply, %{state | buy_order: order}}
  end

  # just bought state
  def handle_cast(
        {:event, %TradeEvent{buyer_order_id: order_id, quantity: quantity}},
        %State{
          symbol: symbol,
          buy_order: %Binance.OrderResponse{
            price: buy_price,
            order_id: order_id,
            orig_qty: quantity
          },
          profit_interval: profit_interval,
          tick_size: tick_size
        } = state
      ) do
    sell_price = calculate_sell_price(buy_price, profit_interval, tick_size)

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_sell(
        symbol,
        quantity,
        sell_price,
        "GTC"
      )

    {:noreply, %{state | sell_order: order}}
  end

  # just sold state
  def handle_cast({:event,
    %TradeEvent{
      seller_order_id: order_id, quantity: quantity
    }},
    %State{
      sell_order: %Binance.OrderResponse{
        order_id: order_id,
        orig_qty: quantity
      }
    } = state
  ) do
    Process.exit(self(), :finished)
    {:noreply, state}
  end

  def handle_cast({:event, _}, state) do
    {:noreply, state}
  end

  defp fetch_tick_size(symbol) do
    %{"filters" => filters} =
      Binance.get_exchange_info()
      |> elem(1)
      |> Map.get(:symbols)
      |> Enum.find(&(&1["symbol"] == String.upcase(symbol)))

    %{"tick_size" => tick_size} =
      filters
      |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))

    tick_size
  end

  defp calculate_sell_price(
    buy_price,
    profit_interval,
    tick_size
  ) do
    fee = D.new("1.001")
    original_price = D.mult(D.new(buy_price), fee)
    tick = D.new(tick_size)

    net_target_price = D.mult(
      original_price,
      D.add("1.0", D.new(profit_interval))
    )

    gross_target_price = D.mult(
      net_target_price,
      fee
    )

    D.to_float(
      D.mult(
        D.div_int(gross_target_price, tick),
        tick
      )
    )
  end
end
