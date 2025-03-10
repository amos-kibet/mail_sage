defmodule MailSage.EmailSyncTest do
  use MailSage.DataCase, async: true

  import Mox

  alias MailSage.Accounts
  alias MailSage.Accounts.GmailAccount
  alias MailSage.Accounts.User
  alias MailSage.EmailSync
  alias MailSage.MockAI
  alias MailSage.MockGmail

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Subscribe test process to PubSub events
    Phoenix.PubSub.subscribe(MailSage.PubSub, "user:*")
    :ok
  end

  describe "schedule_sync/1" do
    # TODO: Fix these tests:
    @describetag :skip
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          google_refresh_token: "test_refresh_token"
        })

      {:ok, gmail_account} =
        Accounts.create_gmail_account(%{
          user_id: user.id,
          email: "test@gmail.com",
          google_refresh_token: "test_refresh_token",
          google_token: "test_token",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600),
          sync_enabled: true,
          is_primary: true
        })

      %{user: user, gmail_account: gmail_account}
    end

    test "successfully schedules sync for user with enabled gmail accounts", %{user: user, gmail_account: gmail_account} do
      expect(MockGmail, :list_new_emails, fn ^gmail_account, _opts ->
        {:ok, %{messages: [], next_page_token: nil}}
      end)

      assert {:ok, pid} = EmailSync.schedule_sync(user.id)
      ref = Process.monitor(pid)

      # Wait for sync completion message
      assert_receive {:sync_complete, user_id} when user_id == user.id, 1000
      # Wait for process to exit
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "handles non-existent user" do
      assert {:ok, pid} = EmailSync.schedule_sync(123_456)
      ref = Process.monitor(pid)

      # Process should exit normally even with error
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      # No sync complete message should be received
      refute_receive {:sync_complete, 123_456}, 100
    end

    test "processes multiple pages of emails", %{user: user, gmail_account: gmail_account} do
      message1 = %{id: "msg1"}
      message2 = %{id: "msg2"}
      email1 = %{id: 1}
      email2 = %{id: 2}

      MockGmail
      |> expect(:list_new_emails, 2, fn
        ^gmail_account, [max_results: 2, q: "is:unread in:inbox", page_token: nil] ->
          {:ok, %{messages: [message1], next_page_token: "next_token"}}

        ^gmail_account, [max_results: 2, q: "is:unread in:inbox", page_token: "next_token"] ->
          {:ok, %{messages: [message2], next_page_token: nil}}
      end)
      |> expect(:import_email, fn
        ^gmail_account, "msg1" -> {:ok, email1}
        ^gmail_account, "msg2" -> {:ok, email2}
      end)

      MockAI
      |> expect(:categorize_email, 2, fn _email, user_id when user_id == user.id -> {:ok, 1} end)
      |> expect(:summarize_email, 2, fn _email -> {:ok, "Summary"} end)

      assert {:ok, pid} = EmailSync.schedule_sync(user.id)
      ref = Process.monitor(pid)

      # Wait for sync completion message
      assert_receive {:sync_complete, user_id} when user_id == user.id, 1000
      # Wait for process to exit
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "skips disabled gmail accounts", %{user: user} do
      # Create a disabled account
      {:ok, _disabled_account} =
        Accounts.create_gmail_account(%{
          user_id: user.id,
          email: "disabled@gmail.com",
          google_refresh_token: "test_refresh_token",
          google_token: "test_token",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600),
          sync_enabled: false,
          is_primary: false
        })

      assert {:ok, pid} = EmailSync.schedule_sync(user.id)
      ref = Process.monitor(pid)

      # Wait for sync completion message (should still be sent even if no accounts processed)
      assert_receive {:sync_complete, user_id} when user_id == user.id, 1000
      # Wait for process to exit
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "handles email processing errors gracefully", %{user: user, gmail_account: gmail_account} do
      message = %{id: "msg1"}

      MockGmail
      |> expect(:list_new_emails, fn ^gmail_account, _opts ->
        {:ok, %{messages: [message], next_page_token: nil}}
      end)
      |> expect(:import_email, fn ^gmail_account, "msg1" ->
        {:error, "Failed to import email"}
      end)

      assert {:ok, pid} = EmailSync.schedule_sync(user.id)
      ref = Process.monitor(pid)

      # Wait for sync completion message
      assert_receive {:sync_complete, user_id} when user_id == user.id, 1000
      # Wait for process to exit
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "handles multiple gmail accounts", %{user: user, gmail_account: gmail_account1} do
      # Create a second account
      {:ok, gmail_account2} =
        Accounts.create_gmail_account(%{
          user_id: user.id,
          email: "second@gmail.com",
          google_refresh_token: "test_refresh_token2",
          google_token: "test_token2",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600),
          sync_enabled: true,
          is_primary: false
        })

      expect(MockGmail, :list_new_emails, 2, fn account, _opts ->
        assert account in [gmail_account1, gmail_account2]
        {:ok, %{messages: [], next_page_token: nil}}
      end)

      assert {:ok, pid} = EmailSync.schedule_sync(user.id)
      ref = Process.monitor(pid)

      # Wait for sync completion message
      assert_receive {:sync_complete, user_id} when user_id == user.id, 1000
      # Wait for process to exit
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end
end
