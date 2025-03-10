defmodule MailSage.Categories.Category do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :description, :string
    field :color, :string
    field :sort_order, :integer

    belongs_to :user, MailSage.Accounts.User
    has_many :emails, MailSage.Emails.Email

    timestamps()
  end

  @doc """
  Creates a changeset for the Category schema.
  """
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :user_id, :color, :sort_order])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_length(:description, max: 500)
    |> validate_format(:color, ~r/^#[0-9A-Fa-f]{6}$/, message: "must be a valid hex color code")
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:name, :user_id], name: :categories_name_user_id_index)
  end
end
