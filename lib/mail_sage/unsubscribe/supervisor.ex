defmodule MailSage.Unsubscribe.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Pool of browser sessions for parallel processing
      {DynamicSupervisor, name: MailSage.Unsubscribe.BrowserPool, strategy: :one_for_one},
      # Queue for managing unsubscribe jobs
      {MailSage.Unsubscribe.Queue, []},
      # Metrics and monitoring
      {MailSage.Unsubscribe.Metrics, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
