defmodule MailSageWeb.PageController do
  use MailSageWeb, :controller

  def home(conn, _params) do
    case conn.assigns.current_user do
      nil -> render(conn, :home, layout: false)
      _user -> redirect(conn, to: ~p"/dashboard")
    end
  end
end
