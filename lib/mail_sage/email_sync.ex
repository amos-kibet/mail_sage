defmodule MailSage.EmailSync do
  @moduledoc """
  Handles syncing and processing emails.
  """

  alias MailSage.Accounts
  alias MailSage.Services.AI
  alias MailSage.Services.Gmail

  require Logger

  @doc """
  Schedule email sync for the current user.
  """
  def schedule_sync(user_id) do
    Task.Supervisor.start_child(MailSage.TaskSupervisor, fn ->
      with {:ok, user} <- fetch_user(user_id) do
        gmail_accounts = Accounts.list_gmail_accounts(user_id)
        # Sync each enabled Gmail account
        gmail_accounts
        |> Enum.filter(& &1.sync_enabled)
        |> Enum.each(fn account ->
          do_sync_emails(user, account, nil)
        end)
      end
    end)
  end

  defp fetch_user(user_id) do
    case Accounts.get_user(user_id) do
      nil ->
        Logger.error("#{__MODULE__}.fetch_user/1: User not found!")
        {:error, :user_not_found}

      user ->
        {:ok, user}
    end
  end

  defp do_sync_emails(user, gmail_account, page_token) do
    with {:ok, %{messages: messages, next_page_token: next_page_token}} <-
           Gmail.list_new_emails(gmail_account,
             max_results: 2,
             q: "is:unread in:inbox",
             page_token: page_token
           ) do
      if messages && length(messages) > 0 do
        process_emails(user, messages, gmail_account)
      end

      if next_page_token do
        do_sync_emails(user, gmail_account, next_page_token)
      else
        Phoenix.PubSub.broadcast(
          MailSage.PubSub,
          "user:#{user.id}",
          {:sync_complete, user.id}
        )

        Logger.info("#{__MODULE__}.do_sync_emails/2: Email sync complete for user #{user.id}")

        # Update last sync time for this account
        {:ok, _} =
          Accounts.update_gmail_account(gmail_account, %{last_sync_at: DateTime.utc_now()})
      end

      :ok
    end
  end

  defp process_emails(user, messages, gmail_account) do
    Enum.each(messages, fn message ->
      with {:ok, email} <- Gmail.import_email(gmail_account, message.id),
           {:ok, category_id} <- AI.categorize_email(email, user.id),
           {:ok, summary} <- AI.summarize_email(email) do
        MailSage.Emails.update_email(email, %{
          category_id: category_id,
          ai_summary: summary
        })
      end
    end)
  end
end
