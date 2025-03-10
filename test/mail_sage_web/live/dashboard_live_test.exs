defmodule MailSageWeb.DashboardLiveTest do
  use MailSageWeb.ConnCase, async: true

  import Mox

  setup :verify_on_exit!

  describe "LIVE /dashboard" do
    setup %{conn: conn} do
      user = insert(:user)
      gmail_account = insert(:gmail_account, user: user)
      category = insert(:category, user: user)
      email = insert(:email, user: user, gmail_account: gmail_account, category: category)

      conn = log_in_user(conn, user)
      {:ok, conn: conn, user: user, gmail_account: gmail_account, category: category, email: email}
    end

    test "displays dashboard with categories and email counts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Dashboard"
      assert html =~ "Category 1"
      assert html =~ "Description for category 1"
      # Email count for the category
      assert html =~ "1"
    end

    # TODO: Fix this test
    @tag :skip
    test "can sync emails", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Mock the sync process
      expect(MailSage.EmailSync.Mock, :schedule_sync, fn _user_id ->
        {:ok, self()}
      end)

      assert view
             |> element("button", "Sync Now")
             |> render_click() =~ "Email sync started"

      # Simulate sync completion
      send(view.pid, {:sync_complete, conn.assigns.current_user.id})

      # assert render(view) =~ "Email sync complete!"
    end

    test "can toggle Gmail account sync", %{conn: conn, gmail_account: gmail_account} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert view
             |> element("button", "Disable sync")
             |> render_click()

      updated_account = MailSage.Accounts.get_gmail_account!(gmail_account.id)
      refute updated_account.sync_enabled

      assert view
             |> element("button", "Enable sync")
             |> render_click()

      updated_account = MailSage.Accounts.get_gmail_account!(gmail_account.id)
      assert updated_account.sync_enabled
    end

    test "can connect new Gmail account", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert view
             |> element("button", "Connect Gmail Account")
             |> render_click()

      # Should redirect to Google OAuth URL
      assert_redirect(view, MailSage.Auth.Google.authorize_url())
    end

    test "handles unmatched info messages gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Send an unmatched info message
      send(view.pid, {:unmatched_message, "test"})

      # The view should still be alive and functioning
      assert view
             |> element("button", "Sync Now")
             |> has_element?()
    end
  end
end
