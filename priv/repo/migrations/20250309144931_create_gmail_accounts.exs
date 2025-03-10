defmodule MailSage.Repo.Migrations.CreateGmailAccounts do
  use Ecto.Migration

  def change do
    create table(:gmail_accounts) do
      add :email, :string, null: false
      add :google_refresh_token, :text
      add :google_token, :text
      add :token_expires_at, :utc_datetime
      add :last_sync_at, :utc_datetime
      add :sync_enabled, :boolean, default: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :is_primary, :boolean, default: false

      timestamps()
    end

    create index(:gmail_accounts, [:user_id])
    create unique_index(:gmail_accounts, [:email, :user_id])
  end
end
