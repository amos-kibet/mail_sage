defmodule MailSageWeb.EmailLiveTest do
  use MailSageWeb.ConnCase, async: true

  import Mox

  alias MailSage.Workers.UnsubscribeWorker.Mock

  setup :verify_on_exit!

  describe "LIVE /emails/:id" do
    setup %{conn: conn} do
      user = insert(:user)
      gmail_account = insert(:gmail_account, user: user)
      category = insert(:category, user: user)

      email =
        insert(:email,
          ai_summary: "Test AI Summary",
          body_html: "<p>Test Body HTML</p>",
          bcc: ["test3@example.com"],
          category: category,
          cc: ["test2@example.com"],
          gmail_account: gmail_account,
          from: "test@example.com",
          subject: "Test Email",
          to: ["test@example.com"],
          user: user
        )

      conn = log_in_user(conn, user)
      {:ok, conn: conn, user: user, gmail_account: gmail_account, category: category, email: email}
    end

    test "displays email details", %{conn: conn, email: email} do
      {:ok, _view, html} = live(conn, ~p"/emails/#{email}")

      assert html =~ email.subject
      assert html =~ email.from
      assert html =~ email.body_html
      assert html =~ email.ai_summary
    end

    # TODO: Fix this test
    @tag :skip
    test "can archive email", %{conn: conn, email: email} do
      expect(MailSage.MockGmail, :archive_email, fn _user, "test123" -> {:ok, %{}} end)
      {:ok, view, _html} = live(conn, ~p"/emails/#{email}")

      assert view
             |> element("button", "Archive")
             |> render_click() =~ "Email archived successfully"

      # Check that the button text changes
      assert render(view) =~ "Unarchive"
    end

    # TODO: Fix this test
    @tag :skip
    test "can unarchive email", %{conn: conn, email: email} do
      # First archive the email
      expect(MailSage.MockGmail, :archive_email, fn _user, "test123" -> {:ok, %{}} end)
      expect(MailSage.MockGmail, :unarchive_email, fn _user, "test123" -> {:ok, %{}} end)
      {:ok, email} = MailSage.Emails.archive_email(email)

      {:ok, view, _html} = live(conn, ~p"/emails/#{email}")

      assert view
             |> element("button", "Unarchive")
             |> render_click() =~ "Email unarchived successfully"

      # Check that the button text changes
      assert render(view) =~ "Archive"
    end

    # TODO: Fix this test
    @tag :skip
    test "can initiate unsubscribe process", %{conn: conn, email: email} do
      # Mock the unsubscribe worker
      expect(Mock, :schedule_unsubscribe, fn email_id ->
        assert email_id == email.id
        {:ok, %{id: "job_id"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/emails/#{email}")

      assert view
             |> element("button", "Unsubscribe")
             |> render_click() =~ "Unsubscribe process started"
    end

    @tag :skip
    test "handles failed unsubscribe gracefully", %{conn: conn, email: email} do
      # Mock the unsubscribe worker to fail
      expect(Mock, :schedule_unsubscribe, fn _email_id ->
        {:error, :failed}
      end)

      {:ok, view, _html} = live(conn, ~p"/emails/#{email}")

      assert view
             |> element("button", "Unsubscribe")
             |> render_click() =~ "Failed to start unsubscribe process"
    end
  end
end
