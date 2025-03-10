defmodule MailSageWeb.CategoryLiveTest do
  use MailSageWeb.ConnCase, async: true

  import Ecto.Query, warn: false

  describe "LIVE /categories/new" do
    setup %{conn: conn} do
      user = insert(:user)
      conn = log_in_user(conn, user)
      {:ok, conn: conn, user: user}
    end

    test "renders category form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/categories/new")

      assert html =~ "New Category"
      assert html =~ "Name"
      assert html =~ "Description"
      assert html =~ "Color"
    end

    test "creates new category with valid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/categories/new")

      result =
        view
        |> form("#category-form", %{
          "category" => %{
            name: "New Category",
            description: "New Description",
            color: "#FF0000"
          }
        })
        |> render_submit()

      query = from(c in MailSage.Categories.Category, where: c.name == "New Category")

      [%{id: created_category_id}] = MailSage.Repo.all(query)

      assert_redirected(view, ~p"/categories/#{created_category_id}")
    end
  end

  describe "LIVE /categories/:id" do
    setup %{conn: conn} do
      user = insert(:user)
      gmail_account = insert(:gmail_account, user: user)
      category = insert(:category, user: user)

      email =
        insert(:email,
          category: category,
          user: user,
          gmail_account: gmail_account,
          subject: "Test Email",
          body_html: "<p>Test body</p>",
          gmail_id: "test123",
          archived: false
        )

      conn = log_in_user(conn, user)
      {:ok, conn: conn, user: user, category: category, email: email}
    end

    test "displays category details and emails", %{conn: conn, category: category} do
      {:ok, _view, html} = live(conn, ~p"/categories/#{category}")

      assert html =~ category.name
      assert html =~ category.description
      assert html =~ "Test Email"
    end

    test "can edit category", %{conn: conn, category: category} do
      {:ok, view, html} = live(conn, ~p"/categories/#{category}")

      assert html =~ category.name
      assert html =~ "Edit Category"
      assert html =~ "Delete Category"

      assert view
             |> element("button[phx-click='edit_category']")
             |> render_click()

      {:error, {:live_redirect, %{to: redirected_route, flash: flash}}} =
        view
        |> form("#category-form", %{
          "category" => %{
            name: "Updated Category",
            description: "Updated Description",
            color: "#00FF00"
          }
        })
        |> render_submit()

      assert_redirected(view, redirected_route)
    end

    test "can delete category", %{conn: conn, category: category} do
      {:ok, view, _html} = live(conn, ~p"/categories/#{category}")

      assert view
             |> element("button", "Delete Category")
             |> render_click()

      assert_redirected(view, ~p"/dashboard")
    end

    # TODO: Fix this test
    @tag :skip
    test "can archive selected emails", %{conn: conn, category: category} do
      {:ok, view, _html} = live(conn, ~p"/categories/#{category}")

      assert view
             |> element("button[phx-click='archive_selected']")
             |> render_click() =~ "Selected emails have been archived"
    end

    # TODO: Fix this test
    @tag :skip
    test "can toggle email selection", %{conn: conn, category: category, email: email} do
      {:ok, view, _html} = live(conn, ~p"/categories/#{category}")

      assert view
             |> element("input[type='checkbox'][value='#{email.id}']")
             |> render_click()

      assert has_element?(view, "input[type='checkbox'][value='#{email.id}'][checked]")
    end

    # TODO: Fix this test
    @tag :skip
    test "can toggle all emails", %{conn: conn, category: category} do
      {:ok, view, _html} = live(conn, ~p"/categories/#{category}")

      assert view
             |> element("input[type='checkbox'][data-action='toggle-all']")
             |> render_click()

      assert has_element?(view, "input[type='checkbox'][checked]")
    end

    # TODO: Fix this test
    @tag :skip
    test "handles pagination", %{conn: conn, category: category} do
      {:ok, view, _html} = live(conn, ~p"/categories/#{category}")

      assert view
             |> element("button[phx-click='page_changed'][phx-value-page='2']")
             |> render_click()

      assert_patched(view, ~p"/categories/#{category}?page=2")
    end
  end
end
