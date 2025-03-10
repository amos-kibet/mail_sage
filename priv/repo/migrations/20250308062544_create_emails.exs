defmodule MailSage.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails) do
      add :gmail_id, :string, null: false
      add :thread_id, :string
      add :subject, :text
      add :from, :string
      add :to, {:array, :string}
      add :cc, {:array, :string}
      add :bcc, {:array, :string}
      add :date, :utc_datetime
      add :snippet, :text
      add :body_html, :text
      add :body_text, :text
      add :ai_summary, :text
      add :labels, {:array, :string}
      add :unsubscribe_link, :text
      add :archived, :boolean, default: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :category_id, references(:categories, on_delete: :nilify_all)

      timestamps()
    end

    create index(:emails, [:user_id])
    create index(:emails, [:category_id])
    create unique_index(:emails, [:gmail_id, :user_id])
  end
end
