defmodule MailSageWeb.LiveView.Hooks.SyncHooks do
  @moduledoc """
  Handles email synchronization when users connect to LiveView.
  """

  # import Phoenix.Component
  import Phoenix.LiveView

  alias MailSage.EmailSync

  require Logger

  def on_mount(:sync, _params, _session, socket) do
    if connected?(socket) && socket.assigns.current_user do
      # Schedule immediate sync when user connects
      Logger.info("#{__MODULE__}.on_mount/4: Scheduling email sync for user #{socket.assigns.current_user.id}")
      EmailSync.schedule_sync(socket.assigns.current_user.id)
    end

    {:cont, socket}
  end
end
