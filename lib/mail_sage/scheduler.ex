defmodule MailSage.Scheduler do
  @moduledoc """
  Handles scheduling of periodic tasks.
  """

  use Quantum, otp_app: :mail_sage

  alias MailSage.Accounts
  alias MailSage.EmailSync

  require Logger

  @doc """
  Syncs emails for all users with sync enabled.
  Runs every minute by default.
  """
  def sync_emails do
    Logger.info("#{__MODULE__}.sync_emails/0: Starting email sync")

    # Get all users with sync enabled
    Enum.each(Accounts.list_users_with_sync_enabled(), fn user ->
      Logger.info("#{__MODULE__}.sync_emails/0: Scheduling email sync for user #{user.id}")
      EmailSync.schedule_sync(user.id)
    end)
  end
end
