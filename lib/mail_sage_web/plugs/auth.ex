defmodule MailSageWeb.Plugs.Auth do
  @moduledoc """
  Authentication plug for handling user sessions.
  """

  import Phoenix.Controller
  import Plug.Conn

  alias MailSage.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    cond do
      conn.assigns[:current_user] ->
        conn

      user_id != nil ->
        assign_current_user(conn, user_id)

      # Otherwise, no user is logged in
      true ->
        assign(conn, :current_user, nil)
    end
  end

  defp assign_current_user(conn, user_id) do
    case Accounts.get_user(user_id) do
      nil ->
        assign(conn, :current_user, nil)

      user ->
        :ok =
          Phoenix.PubSub.broadcast(
            MailSage.PubSub,
            "user:#{user_id}",
            {:current_user_id, user_id}
          )

        assign(conn, :current_user, user)
    end
  end

  @doc """
  Used as a plug to require authentication.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page.")
      |> redirect(to: "/")
      |> halt()
    end
  end

  @doc """
  Used as a plug to redirect authenticated users away from auth pages.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: "/dashboard")
      |> halt()
    else
      conn
    end
  end
end
