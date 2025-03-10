defmodule MailSage.Unsubscribe.Metrics do
  @moduledoc """
  Handles metrics collection for the unsubscribe system.
  """

  use GenServer

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def increment(metric) do
    GenServer.cast(__MODULE__, {:increment, metric})
  end

  def gauge(metric, value) do
    GenServer.cast(__MODULE__, {:gauge, metric, value})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{counters: %{}, gauges: %{}}}
  end

  @impl true
  def handle_cast({:increment, metric}, state) do
    new_counters = Map.update(state.counters, metric, 1, &(&1 + 1))

    :telemetry.execute(
      [:mail_sage, :unsubscribe, metric],
      %{count: Map.get(new_counters, metric)},
      %{}
    )

    {:noreply, %{state | counters: new_counters}}
  end

  @impl true
  def handle_cast({:gauge, metric, value}, state) do
    new_gauges = Map.put(state.gauges, metric, value)

    :telemetry.execute(
      [:mail_sage, :unsubscribe, metric],
      %{value: value},
      %{}
    )

    {:noreply, %{state | gauges: new_gauges}}
  end
end
