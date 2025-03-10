defmodule MailSage.Auth.Google.Client do
  @moduledoc """
  Handles Google API operations for fetching and managing Gmail connections.
  """

  @behaviour MailSage.Auth.Google

  alias GoogleApi.Gmail.V1.Connection
  alias MailSage.Accounts
  alias MailSage.Auth.Google

  require Logger

  @oauth_scopes [
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.readonly"
  ]

  @impl Google
  def get_gmail_conn(%{google_token: token} = gmail_account) when not is_nil(token) do
    if Accounts.token_expired?(gmail_account) do
      refresh_user_token(gmail_account)
    else
      {:ok, Connection.new(gmail_account.google_token)}
    end
  end

  def get_gmail_conn(_user), do: {:error, :no_token}

  @impl Google
  def refresh_user_token(user) do
    with {:ok, %{access_token: access_token, expires_at: expires_at}} <-
           get_refresh_access_token(user.google_refresh_token),
         {:ok, _user} <-
           Accounts.update_user_tokens(user, %{
             google_token: access_token,
             token_expires_at: expires_at
           }) do
      {:ok, Connection.new(access_token)}
    end
  end

  @impl Google
  def oauth_client(strategy \\ OAuth2.Strategy.AuthCode) do
    client_id = Application.fetch_env!(:mail_sage, :google_client_id)
    client_secret = Application.fetch_env!(:mail_sage, :google_client_secret)
    redirect_uri = Application.fetch_env!(:mail_sage, :google_redirect_uri)

    OAuth2.Client.new(
      strategy: strategy,
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      site: "https://accounts.google.com",
      authorize_url: "/o/oauth2/v2/auth",
      token_url: "https://oauth2.googleapis.com/token"
    )
  end

  @impl Google
  def authorize_url(_opts \\ []) do
    oauth_client = oauth_client()

    OAuth2.Client.authorize_url!(oauth_client,
      scope: Enum.join(@oauth_scopes, " "),
      access_type: "offline",
      prompt: "consent select_account"
    )
  end

  @impl Google
  def exchange_code_for_token(code) do
    case OAuth2.Client.get_token(oauth_client(), code: code) do
      {:ok, client} ->
        decoded = Jason.decode!(client.token.access_token)

        {:ok,
         %{
           access_token: decoded["access_token"],
           refresh_token: decoded["refresh_token"],
           expires_at: get_token_expires_at(decoded["expires_in"])
         }}

      {:error, %{body: body}} ->
        Logger.error("Error getting OAuth access token:\n#{inspect(body)}")
        {:error, body}
    end
  end

  @impl Google
  def get_refresh_access_token(refresh_token) do
    client = oauth_client(OAuth2.Strategy.Refresh)

    case OAuth2.Client.get_token(client,
           grant_type: "refresh_token",
           refresh_token: refresh_token
         ) do
      {:ok, client} ->
        decoded = Jason.decode!(client.token.access_token)

        {:ok,
         %{
           access_token: decoded["access_token"],
           expires_at: get_token_expires_at(decoded["expires_in"])
         }}

      {:error, %{body: body}} ->
        Logger.error("Error getting OAuth refresh token:\n#{inspect(body)}")
        {:error, body}
    end
  end

  defp get_token_expires_at(expiry_in_seconds) do
    DateTime.add(DateTime.utc_now(), expiry_in_seconds, :second)
  end

  @impl Google
  def get_user_info(access_token) do
    request =
      Finch.build(:get, "https://www.googleapis.com/oauth2/v2/userinfo", [
        {"Authorization", "Bearer #{access_token}"}
      ])

    case Finch.request(request, MailSage.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %Finch.Response{body: body}} ->
        {:error, Jason.decode!(body)}

      {:error, reason} ->
        # TODO: Configure Appsignal
        Logger.error("Error getting user_info:\n#{inspect(reason)}")
        {:error, reason}
    end
  end
end
