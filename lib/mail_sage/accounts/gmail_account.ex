defmodule MailSage.Accounts.GmailAccount do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "gmail_accounts" do
    field :email, :string
    field :google_refresh_token, :string
    field :google_token, :string
    field :token_expires_at, :utc_datetime
    field :last_sync_at, :utc_datetime
    field :sync_enabled, :boolean, default: true
    field :is_primary, :boolean, default: false

    belongs_to :user, MailSage.Accounts.User
    has_many :emails, MailSage.Emails.Email

    timestamps()
  end

  def changeset(gmail_account, attrs) do
    gmail_account
    |> cast(attrs, [
      :email,
      :google_refresh_token,
      :google_token,
      :token_expires_at,
      :last_sync_at,
      :sync_enabled,
      :is_primary,
      :user_id
    ])
    |> validate_required([:email, :google_refresh_token, :user_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint([:email, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
