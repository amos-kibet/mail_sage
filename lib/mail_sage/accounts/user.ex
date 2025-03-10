defmodule MailSage.Accounts.User do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :google_refresh_token, :string
    field :google_token, :string
    field :google_user_image, :string
    field :token_expires_at, :utc_datetime
    field :last_sync_at, :utc_datetime
    field :sync_enabled, :boolean, default: true
    field :settings, :map, default: %{}

    has_many :categories, MailSage.Categories.Category
    has_many :emails, MailSage.Emails.Email
    has_many :gmail_accounts, MailSage.Accounts.GmailAccount

    timestamps()
  end

  @doc """
  Creates a changeset for the User schema.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :google_refresh_token,
      :google_token,
      :google_user_image,
      :token_expires_at,
      :last_sync_at,
      :sync_enabled,
      :settings
    ])
    |> validate_required([:email, :google_refresh_token])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
  end

  @doc """
  Creates a changeset for updating Google OAuth tokens.
  """
  def token_changeset(user, attrs) do
    user
    |> cast(attrs, [:google_refresh_token, :google_token, :token_expires_at])
    |> validate_required([:google_refresh_token, :google_token, :token_expires_at])
  end

  @doc """
  Creates a changeset for updating sync settings.
  """
  def sync_changeset(user, attrs) do
    user
    |> cast(attrs, [:sync_enabled, :last_sync_at])
    |> validate_required([:sync_enabled])
  end
end
