defmodule MailSageWeb.AuthController do
  use MailSageWeb, :controller

  alias MailSage.Accounts
  alias MailSage.Auth.Google

  require Logger

  def google(conn, params) do
    url =
      if params["force"],
        do: Google.authorize_url(force_consent: true),
        else: Google.authorize_url()

    redirect(conn, external: url)
  end

  def google_callback(conn, %{"code" => code}) do
    case Google.exchange_code_for_token(code) do
      {:ok, token_info} ->
        case Google.get_user_info(token_info.access_token) do
          {:ok, user_info} ->
            if conn.assigns.current_user do
              # Adding additional Gmail account to existing user
              handle_additional_account(conn, conn.assigns.current_user, user_info, token_info)
            else
              # First-time login or returning user
              case Accounts.get_user_by_email(user_info["email"]) do
                nil ->
                  # Create new user
                  {:ok, user} = upsert_user(user_info, token_info)

                  conn
                  |> put_session(:user_id, user.id)
                  |> configure_session(renew: true)
                  |> redirect(to: ~p"/dashboard")

                existing_user ->
                  # Update existing user's tokens
                  {:ok, user} =
                    Accounts.update_user_tokens(existing_user, %{
                      google_token: token_info.access_token,
                      google_refresh_token: token_info.refresh_token,
                      token_expires_at: token_info.expires_at
                    })

                  conn
                  |> put_session(:user_id, user.id)
                  |> configure_session(renew: true)
                  |> redirect(to: ~p"/dashboard")
              end
            end

          {:error, error} ->
            Logger.error("#{__MODULE__}.google_callback/2: Google authentication error\n#{inspect(error)}")

            conn
            |> put_flash(:error, "Failed to get user info from Google")
            |> redirect(to: ~p"/")
        end

      {:error, :no_refresh_token} ->
        redirect(conn, to: ~p"/auth/google?force=true")

      {:error, error} ->
        Logger.error("#{__MODULE__}.google_callback/2: Google authentication error\n#{inspect(error)}")

        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: ~p"/")
    end
  end

  def google_callback(conn, %{"error" => error}) do
    Logger.error("#{__MODULE__}.google_callback/2: Google authentication error\n#{inspect(error)}")

    conn
    |> put_flash(:error, "Error signing in with Google\nMessage: #{error}")
    |> redirect(to: ~p"/")
  end

  # Handle adding additional Gmail account
  defp handle_additional_account(conn, current_user, user_info, token_info) do
    attrs = %{
      email: user_info["email"],
      google_refresh_token: token_info.refresh_token,
      google_token: token_info.access_token,
      is_primary: false,
      sync_enabled: true,
      token_expires_at: token_info.expires_at,
      user_id: current_user.id
    }

    case Accounts.create_gmail_account(attrs) do
      {:ok, _gmail_account} ->
        conn
        |> put_flash(:info, "Gmail account connected successfully!")
        |> redirect(to: ~p"/dashboard")

      {:error, %Ecto.Changeset{errors: [email: {"has already been taken", _opts}]}} ->
        conn
        |> put_flash(:error, "This Gmail account is already connected.")
        |> redirect(to: ~p"/dashboard")

      {:error, error} ->
        Logger.error("#{__MODULE__}.handle_additional_account/4: Error creating Gmail account\n#{inspect(error)}")

        conn
        |> put_flash(:error, "Failed to connect Gmail account!")
        |> redirect(to: ~p"/dashboard")
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  defp upsert_user(user_info, token_info) do
    attrs = %{
      email: user_info["email"],
      google_token: token_info.access_token,
      google_refresh_token: token_info.refresh_token,
      google_user_image: user_info["picture"],
      token_expires_at: token_info.expires_at
    }

    case Accounts.get_user_by_email(user_info["email"]) do
      nil ->
        MailSage.Repo.transaction(fn ->
          {:ok, user} = Accounts.create_user(attrs)

          gmail_account_attrs = %{
            email: user_info["email"],
            google_refresh_token: token_info.refresh_token,
            google_token: token_info.access_token,
            is_primary: true,
            sync_enabled: true,
            token_expires_at: token_info.expires_at,
            user_id: user.id
          }

          {:ok, _gmail_account} = Accounts.create_gmail_account(gmail_account_attrs)

          user
        end)

      user ->
        Accounts.update_user_tokens(user, attrs)
    end
  end
end
