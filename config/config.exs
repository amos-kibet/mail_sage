# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  mail_sage: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure OpenAI
config :ex_openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  organization_key: System.get_env("OPENAI_ORGANIZATION_KEY"),
  http_options: [recv_timeout: 30_000]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :mail_sage, MailSage.Mailer, adapter: Swoosh.Adapters.Local

# Configure Quantum for scheduled tasks
config :mail_sage, MailSage.Scheduler,
  jobs: [
    {"* * * * *", {MailSage.Scheduler, :sync_emails, []}}
  ]

# Configures the endpoint
config :mail_sage, MailSageWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MailSageWeb.ErrorHTML, json: MailSageWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MailSage.PubSub,
  live_view: [signing_salt: "cXDBJTlo"]

config :mail_sage,
  ecto_repos: [MailSage.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure OAuth2
config :mail_sage,
  google_client_id: System.get_env("GOOGLE_CLIENT_ID"),
  google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
  google_redirect_uri: System.get_env("GOOGLE_REDIRECT_URI")

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Wallaby
config :tailwind,
  version: "3.4.3",
  mail_sage: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# config :wallaby,
#   driver: Wallaby.Chrome,
#   chrome: [
#     headless: true
#   ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
