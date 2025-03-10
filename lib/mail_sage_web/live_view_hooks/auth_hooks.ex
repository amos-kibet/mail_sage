defmodule MailSageWeb.LiveViewHooks.AuthHooks do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView

  alias MailSage.Accounts

  def on_mount(:default, _params, session, socket) do
    if user_id = session["user_id"] do
      case Accounts.get_user(user_id) do
        nil ->
          {:halt, redirect(socket, to: "/")}

        user ->
          :ok =
            Phoenix.PubSub.broadcast(
              MailSage.PubSub,
              "user:#{user_id}",
              {:current_user_id, user_id}
            )

          {:cont, assign(socket, current_user: user)}
      end
    else
      {:halt, redirect(socket, to: "/")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    if user_id = session["user_id"] do
      case Accounts.get_user(user_id) do
        nil ->
          {:cont, assign(socket, current_user: nil)}

        _user ->
          {:halt, redirect(socket, to: "/dashboard")}
      end
    else
      {:cont, assign(socket, current_user: nil)}
    end
  end
end
