defmodule MailSage.Scheduler do
  @moduledoc """
  Handles scheduling of periodic tasks.
  """

  use Quantum, otp_app: :mail_sage

  alias MailSage.EmailSync

  require Logger

  @doc """
  Schedules email sync for the current user.
  Runs every minute by default.
  """
  def sync_emails do
    :ok =
      Phoenix.PubSub.subscribe(MailSage.PubSub, "user:*")

    receive do
      {:current_user_id, user_id} ->
        Logger.info("#{__MODULE__}.sync_emails/0: Scheduling email sync for user #{user_id}")
        EmailSync.schedule_sync(user_id)

      other ->
        Logger.warning("#{__MODULE__}.sync_emails/0: Received unexpected message: #{inspect(other)}")
    after
      5000 ->
        # TODO: Continue from here; we don't receive the user ID in the last 5 seconds
        # Timeout after 5 seconds if no user ID received

        Logger.warning("#{__MODULE__}.sync_emails/0: No user ID received in the last 5 seconds")
        :timeout
    end
  end
end
