defmodule MailSage.Repo do
  use Ecto.Repo,
    otp_app: :mail_sage,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 10
end
