defmodule MailSage.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false
      add :description, :text
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :color, :string
      add :sort_order, :integer

      timestamps()
    end

    create index(:categories, [:user_id])
    create unique_index(:categories, [:name, :user_id], name: :categories_name_user_id_index)
  end
end
