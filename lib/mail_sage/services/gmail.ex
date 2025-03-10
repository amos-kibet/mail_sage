defmodule MailSage.Services.Gmail do
  @moduledoc """
  Handles Gmail API operations for fetching and managing emails.
  """

  @callback list_new_emails(map(), keyword()) ::
              {:ok, %{messages: list(), next_page_token: String.t() | nil}}
              | {:error, any()}

  @callback import_email(map(), String.t()) ::
              {:ok, map()} | {:error, any()}

  @callback get_email(map(), String.t(), keyword()) ::
              {:ok, map()} | {:error, any()}

  @callback archive_email(map(), String.t()) ::
              {:ok, map()} | {:error, any()}

  @callback unarchive_email(map(), String.t()) ::
              {:ok, map()} | {:error, any()}

  @callback bulk_modify_messages(map(), list(), keyword()) ::
              {:ok, nil} | {:error, any()}

  defp gmail_client do
    Application.get_env(:mail_sage, :gmail_client, MailSage.Services.Gmail.Client)
  end

  @doc """
  Lists emails from Gmail that haven't been processed yet.

  ## Options
    * `:max_results` - Maximum number of messages to return
    * `:page_token` - Page token from a previous request
    * `:label_ids` - Only return messages with these label IDs
    * `:q` - Search query (same format as Gmail search box)
  """
  def list_new_emails(gmail_account, opts \\ []) do
    gmail_client().list_new_emails(gmail_account, opts)
  end

  @doc """
  Imports a new email from Gmail into our database.
  """
  def import_email(gmail_account, email_id) do
    gmail_client().import_email(gmail_account, email_id)
  end

  @doc """
  Fetches full email details from Gmail.

  ## Options
    * `:format` - The format to return the message in. Defaults to "full"
    * `:metadata_headers` - List of headers to include when format is "metadata"
  """
  def get_email(gmail_account, email_id, opts \\ []) do
    gmail_client().get_email(gmail_account, email_id, opts)
  end

  @doc """
  Archives an email in Gmail by removing the INBOX label.
  Returns {:ok, message} on success.
  """
  def archive_email(gmail_account, email_id) do
    gmail_client().archive_email(gmail_account, email_id)
  end

  @doc """
  Unarchives an email in Gmail by adding the INBOX label.
  Returns {:ok, message} on success.
  """
  def unarchive_email(gmail_account, email_id) do
    gmail_client().unarchive_email(gmail_account, email_id)
  end

  @doc """
  Bulk modifies messages in Gmail.
  Returns {:ok, nil} on success.
  """
  def bulk_modify_messages(gmail_account, message_ids, opts \\ []) do
    gmail_client().bulk_modify_messages(gmail_account, message_ids, opts)
  end
end
