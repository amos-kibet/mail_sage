defmodule MailSageWeb.Router do
  use MailSageWeb, :router

  alias MailSageWeb.Plugs.Auth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MailSageWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Auth
  end

  pipeline :require_auth do
    plug Auth, :require_authenticated_user
  end

  pipeline :redirect_if_authenticated do
    plug Auth, :redirect_if_user_is_authenticated
  end

  # Public routes
  scope "/", MailSageWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/", PageController, :home
  end

  # Authentication routes
  scope "/auth", MailSageWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/google", AuthController, :google
    get "/google/callback", AuthController, :google_callback
  end

  # Protected routes
  scope "/", MailSageWeb do
    pipe_through [:browser, :require_auth]

    live_session :authenticated,
      on_mount: {MailSageWeb.LiveViewHooks.AuthHooks, :default} do
      delete "/logout", AuthController, :delete
      live "/dashboard", DashboardLive, :index
      live "/categories/new", CategoryLive, :new
      live "/categories/:id", CategoryLive, :show
      live "/categories/:id/edit", CategoryLive, :edit
      live "/emails/:id", EmailLive, :show
    end
  end

  if Application.compile_env(:mail_sage, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MailSageWeb.Telemetry
    end
  end
end
