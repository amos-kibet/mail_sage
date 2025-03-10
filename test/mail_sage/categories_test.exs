defmodule MailSage.CategoriesTest do
  use MailSage.DataCase, async: true

  alias MailSage.Accounts
  alias MailSage.Categories
  alias MailSage.Categories.Category

  @valid_attrs %{
    name: "Important",
    color: "#FF0000",
    description: "Important emails",
    rules: %{
      "conditions" => ["from:example.com", "subject:urgent"],
      "actions" => ["mark_important", "star"]
    }
  }
  @update_attrs %{
    name: "Very Important",
    color: "#00FF00",
    description: "Very important emails"
  }
  @invalid_attrs %{name: nil, color: nil, description: nil, user_id: nil}

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        google_refresh_token: "refresh_token"
      })

    {:ok, user: user}
  end

  describe "list_categories/1" do
    test "returns all categories for a user", %{user: user} do
      category1 = category_fixture(%{name: "Category 1", user_id: user.id})
      category2 = category_fixture(%{name: "Category 2", user_id: user.id})

      # Create a category for a different user to ensure it's not returned
      {:ok, other_user} = create_user("other@example.com")
      _other_category = category_fixture(%{name: "Other Category", user_id: other_user.id})

      categories = Categories.list_categories(user.id)
      assert length(categories) == 2
      assert categories |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([category1.id, category2.id])
    end

    test "returns empty list when user has no categories", %{user: user} do
      assert Categories.list_categories(user.id) == []
    end

    test "returns categories in alphabetical order by name", %{user: user} do
      category_fixture(%{name: "Zebra", user_id: user.id})
      category_fixture(%{name: "Alpha", user_id: user.id})
      category_fixture(%{name: "Beta", user_id: user.id})

      categories = Categories.list_categories(user.id)
      names = Enum.map(categories, & &1.name)
      assert names == ["Alpha", "Beta", "Zebra"]
    end
  end

  describe "get_user_category/2" do
    test "returns category when it exists and belongs to user", %{user: user} do
      category = category_fixture(%{user_id: user.id})
      found_category = Categories.get_user_category(user.id, category.id)
      assert found_category.id == category.id
    end

    test "returns nil when category doesn't exist", %{user: user} do
      assert Categories.get_user_category(user.id, -1) == nil
    end

    test "returns nil when category belongs to different user", %{user: user} do
      {:ok, other_user} = create_user("other@example.com")
      category = category_fixture(%{user_id: other_user.id})
      assert Categories.get_user_category(user.id, category.id) == nil
    end
  end

  describe "create_category/1" do
    test "creates category with valid data", %{user: user} do
      attrs = Map.put(@valid_attrs, :user_id, user.id)
      assert {:ok, %Category{} = category} = Categories.create_category(attrs)
      assert category.name == "Important"
      assert category.color == "#FF0000"
      assert category.description == "Important emails"
      assert category.user_id == user.id
    end

    test "returns error changeset with invalid data" do
      assert {:error, %Ecto.Changeset{}} = Categories.create_category(@invalid_attrs)
    end

    test "returns error when trying to create duplicate category name for same user", %{user: user} do
      attrs = Map.put(@valid_attrs, :user_id, user.id)
      assert {:ok, %Category{}} = Categories.create_category(attrs)
      assert {:error, changeset} = Categories.create_category(attrs)
      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "update_category/2" do
    test "updates category with valid data", %{user: user} do
      category = category_fixture(%{user_id: user.id})
      assert {:ok, category} = Categories.update_category(category, @update_attrs)
      assert category.name == "Very Important"
      assert category.color == "#00FF00"
      assert category.description == "Very important emails"
    end

    test "returns error changeset with invalid data", %{user: user} do
      category = category_fixture(%{user_id: user.id})
      assert {:error, %Ecto.Changeset{}} = Categories.update_category(category, @invalid_attrs)
      assert category == Categories.get_user_category(user.id, category.id)
    end
  end

  defp create_user(email) do
    Accounts.create_user(%{
      email: email,
      google_refresh_token: "refresh_token"
    })
  end

  defp category_fixture(attrs) do
    {:ok, category} =
      attrs
      |> Enum.into(@valid_attrs)
      |> Categories.create_category()

    category
  end
end
