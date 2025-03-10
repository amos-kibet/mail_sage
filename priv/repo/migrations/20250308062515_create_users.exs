defmodule MailSage.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :google_refresh_token, :text
      add :google_token, :text
      add :google_user_image, :text
      add :token_expires_at, :utc_datetime
      add :last_sync_at, :utc_datetime
      add :sync_enabled, :boolean, default: true
      add :settings, :map, default: %{}

      timestamps()
    end

    create unique_index(:users, [:email])
  end
end
