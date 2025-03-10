defmodule MailSage.Auth.Google do
  @moduledoc """
  Handles Google OAuth authentication and token management.
  """

  @callback get_gmail_conn(map()) :: {:ok, map()} | {:error, any()}
  @callback get_refresh_access_token(String.t()) :: {:ok, map()} | {:error, any()}
  @callback get_user_info(String.t()) :: {:ok, map()} | {:error, any()}
  @callback refresh_user_token(map()) :: {:ok, map()} | {:error, any()}
  @callback oauth_client(any()) :: OAuth2.Client.t()
  @callback authorize_url(keyword()) :: String.t()
  @callback exchange_code_for_token(String.t()) :: {:ok, map()} | {:error, any()}

  defp google_client do
    Application.get_env(:mail_sage, :google_client, MailSage.Auth.Google.Client)
  end

  def oauth_client(strategy \\ OAuth2.Strategy.AuthCode) do
    google_client().oauth_client(strategy)
  end

  @doc """
  Generates the authorization URL for Google OAuth.
  """
  def authorize_url(opts \\ []) do
    google_client().authorize_url(opts)
  end

  @doc """
  Exchanges an authorization code for tokens.
  """
  def exchange_code_for_token(code) do
    google_client().exchange_code_for_token(code)
  end

  @doc """
  Refreshes an expired access token using the refresh token.
  """
  def get_refresh_access_token(refresh_token) do
    google_client().get_refresh_access_token(refresh_token)
  end

  @doc """
  Gets user info from Google using the access token.
  """
  def get_user_info(access_token) do
    google_client().get_user_info(access_token)
  end

  @doc """
  Creates a Gmail API connection for a user. We pass in a GmailAccount struct.
  Automatically refreshes the access token if expired.
  """
  def get_gmail_conn(gmail_account) do
    google_client().get_gmail_conn(gmail_account)
  end

  @doc """
  Refreshes a user's access token and updates it in the database.
  """
  def refresh_user_token(user) do
    google_client().refresh_user_token(user)
  end
end
