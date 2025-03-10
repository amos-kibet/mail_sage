defmodule MailSage.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MailSageWeb.Telemetry,
      MailSage.Repo,
      {DNSCluster, query: Application.get_env(:mail_sage, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MailSage.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: MailSage.Finch},
      # Start a worker by calling: MailSage.Worker.start_link(arg)
      # {MailSage.Worker, arg},
      # Start to serve requests, typically the last entry
      MailSageWeb.Endpoint,
      {Task.Supervisor, name: MailSage.TaskSupervisor},
      MailSage.Scheduler
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MailSage.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MailSageWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
