defmodule MailSage.Categories do
  @moduledoc """
  The Categories context handles email category management.
  """

  import Ecto.Query, warn: false

  alias MailSage.Categories.Category
  alias MailSage.Repo

  @doc """
  Lists all categories for a user.
  Categories are shared across all Gmail accounts for the same user.
  """
  def list_categories(user_id) do
    Category
    |> where(user_id: ^user_id)
    |> order_by([c], c.name)
    |> Repo.all()
  end

  @doc """
  Gets a single category for a specific user.
  Returns nil if the category does not exist or doesn't belong to the user.
  """
  def get_user_category(user_id, category_id) do
    Category
    |> where(user_id: ^user_id, id: ^category_id)
    |> Repo.one()
  end

  @doc """
  Creates a category.
  """
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.
  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.
  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end
end
