defmodule MailSage.EmailsTest do
  use MailSage.DataCase, async: true

  import Ecto.Query
  import Mox

  alias MailSage.Emails
  alias MailSage.Emails.Email
  alias MailSage.Repo

  setup :verify_on_exit!

  setup do
    user = insert(:user)
    category = insert(:category, user: user)
    gmail_account = insert(:gmail_account, user: user)

    %{
      user: user,
      category: category,
      gmail_account: gmail_account
    }
  end

  describe "list_emails/2" do
    test "returns paginated list of emails for a user", %{user: user} do
      # Create 15 emails to test pagination
      _emails =
        for n <- 0..15 do
          insert(:email, user: user, subject: "Email #{n}")
        end

      # Test default pagination (page 1, per_page 10)
      result = Emails.list_emails(user.id)
      assert result.page_size == 10
      # 15 + 1 from setup
      assert result.total_entries == 16
      assert length(result.entries) == 10

      # Test custom pagination
      result = Emails.list_emails(user.id, page: 2, per_page: 5)
      assert result.page_size == 5
      assert length(result.entries) == 5
      assert result.page_number == 2
    end

    test "filters by category", %{user: user, category: category} do
      categorized_email = insert(:email, user: user, category: category)
      _uncategorized_email = insert(:email, user: user)

      result = Emails.list_emails(user.id, category_id: category.id)

      assert length(result.entries) == 1
      assert hd(result.entries).id == categorized_email.id
    end

    test "filters by archived status", %{user: user} do
      archived_email = insert(:email, user: user, archived: true)
      unarchived_email = insert(:email, user: user, archived: false)

      result = Emails.list_emails(user.id, archived: true)
      assert length(result.entries) == 1
      assert hd(result.entries).id == archived_email.id

      result = Emails.list_emails(user.id, archived: false)
      assert Enum.find(result.entries, &(&1.id == unarchived_email.id))
    end
  end

  describe "get_user_email/2" do
    setup(%{user: user}) do
      gmail_account = insert(:gmail_account, user: user)

      email =
        insert(:email,
          user: user,
          gmail_account: gmail_account,
          subject: "Test Email",
          body_html: "<p>Test body</p>",
          gmail_id: "test123",
          archived: false
        )

      %{user: user, email: email}
    end

    test "returns email if it belongs to user", %{user: user, email: email} do
      assert %Email{} = fetched_email = Emails.get_user_email(user.id, email.id)
      assert fetched_email.id == email.id
    end

    test "returns nil if email doesn't belong to user", %{email: email} do
      other_user = insert(:user)
      assert is_nil(Emails.get_user_email(other_user.id, email.id))
    end

    test "returns nil if email doesn't exist", %{user: user} do
      assert is_nil(Emails.get_user_email(user.id, -1))
    end
  end

  describe "create_email/1" do
    test "creates email with valid attributes", %{user: user} do
      gmail_account = insert(:gmail_account, user: user)

      valid_attrs = %{
        user_id: user.id,
        gmail_account_id: gmail_account.id,
        subject: "New Email",
        body_html: "<p>Content</p>",
        gmail_id: "new123",
        date: ~N[2024-03-20 10:00:00]
      }

      assert {:ok, %Email{} = email} = Emails.create_email(valid_attrs)
      assert email.subject == "New Email"
      assert email.gmail_id == "new123"
    end

    test "returns error with invalid attributes" do
      assert {:error, %Ecto.Changeset{}} = Emails.create_email(%{})
    end
  end

  describe "update_email/2" do
    setup(%{user: user}) do
      gmail_account = insert(:gmail_account, user: user)

      email =
        insert(:email,
          user: user,
          gmail_account: gmail_account,
          subject: "Test Email",
          body_html: "<p>Test body</p>",
          gmail_id: "test123",
          archived: false
        )

      %{email: email}
    end

    test "updates email with valid attributes", %{email: email} do
      update_attrs = %{subject: "Updated Subject"}

      assert {:ok, %Email{} = updated_email} = Emails.update_email(email, update_attrs)
      assert updated_email.subject == "Updated Subject"
    end

    test "returns error with invalid attributes", %{email: email} do
      assert {:error, %Ecto.Changeset{}} = Emails.update_email(email, %{gmail_id: nil})
    end
  end

  describe "categorize_email/2" do
    setup(%{user: user}) do
      category = insert(:category, user: user)
      gmail_account = insert(:gmail_account, user: user)

      email =
        insert(:email,
          user: user,
          gmail_account: gmail_account,
          subject: "Test Email",
          body_html: "<p>Test body</p>",
          gmail_id: "test123",
          archived: false
        )

      %{email: email, category: category}
    end

    test "assigns category to email", %{email: email, category: category} do
      assert {:ok, updated_email} = Emails.categorize_email(email, category.id)
      assert updated_email.category_id == category.id
    end

    test "removes category when nil is provided", %{email: email, category: category} do
      # First categorize the email
      {:ok, categorized_email} = Emails.categorize_email(email, category.id)
      assert categorized_email.category_id == category.id

      # Then remove the category
      assert {:ok, updated_email} = Emails.categorize_email(categorized_email, nil)
      assert is_nil(updated_email.category_id)
    end
  end

  describe "archive_email/2" do
    test "archives email successfully", %{user: user} do
      gmail_account = insert(:gmail_account, user: user)

      email =
        insert(:email,
          user: user,
          gmail_account: gmail_account,
          subject: "Test Email",
          body_html: "<p>Test body</p>",
          gmail_id: "test123",
          archived: false
        )

      expect(MailSage.MockGmail, :archive_email, fn _user, "test123" -> {:ok, nil} end)

      assert {:ok, updated_email} = Emails.archive_email(email)
      assert updated_email.archived == true
    end

    test "unarchives email successfully", %{user: user} do
      gmail_account = insert(:gmail_account, user: user)

      email =
        insert(:email,
          user: user,
          gmail_account: gmail_account,
          subject: "Test Email",
          body_html: "<p>Test body</p>",
          gmail_id: "test123",
          archived: true
        )

      # First archive the email
      Repo.update!(Ecto.Changeset.change(email, archived: true))

      expect(MailSage.MockGmail, :unarchive_email, fn _user, "test123" -> {:ok, nil} end)

      assert {:ok, updated_email} = Emails.archive_email(email, false)
      assert updated_email.archived == false
    end

    test "handles Gmail API failure", %{user: user} do
      gmail_account = insert(:gmail_account, user: user)

      email =
        insert(:email,
          user: user,
          gmail_account: gmail_account,
          subject: "Test Email",
          body_html: "<p>Test body</p>",
          gmail_id: "test123",
          archived: false
        )

      expect(MailSage.MockGmail, :archive_email, fn _user, "test123" -> {:error, :api_error} end)

      assert {:error, :api_error} = Emails.archive_email(email)
      # Verify email remains unarchived
      assert Repo.reload!(email).archived == false
    end
  end

  describe "bulk_archive_emails/2" do
    test "archives multiple emails", %{user: user, gmail_account: gmail_account} do
      emails =
        for i <- 1..3 do
          gmail_id = "test#{i}"

          insert(:email,
            user: user,
            gmail_account: gmail_account,
            archived: false,
            gmail_id: gmail_id
          )
        end

      email_ids = Enum.map(emails, & &1.id)

      # Expect Gmail API calls for each email
      for email <- emails do
        expect(MailSage.MockGmail, :archive_email, fn _user, gmail_id when gmail_id == email.gmail_id ->
          {:ok, nil}
        end)
      end

      Emails.bulk_archive_emails(email_ids)

      # Verify all emails are archived
      archived_count = Email |> where([e], e.id in ^email_ids and e.archived == true) |> Repo.aggregate(:count)
      assert archived_count == 3
    end
  end

  describe "bulk_categorize_emails/2" do
    test "categorizes multiple emails" do
      user = insert(:user)
      category = insert(:category, user: user)

      emails =
        for _ <- 1..3 do
          insert(:email, user: user)
        end

      email_ids = Enum.map(emails, & &1.id)

      Emails.bulk_categorize_emails(email_ids, category.id)

      # Verify all emails are categorized
      categorized_count =
        Email
        |> where([e], e.id in ^email_ids and e.category_id == ^category.id)
        |> Repo.aggregate(:count)

      assert categorized_count == 3
    end
  end

  describe "get_by_gmail_id/2" do
    setup(%{user: user}) do
      gmail_account = insert(:gmail_account, user: user)

      email =
        insert(:email,
          user: user,
          gmail_account: gmail_account,
          subject: "Test Email",
          body_html: "<p>Test body</p>",
          gmail_id: "test123",
          archived: false
        )

      %{email: email, user: user}
    end

    test "returns email with matching gmail_id and user_id", %{email: email, user: user} do
      assert %Email{} = found_email = Emails.get_by_gmail_id(email.gmail_id, user.id)
      assert found_email.id == email.id
    end

    test "returns nil when gmail_id doesn't exist" do
      user = insert(:user)
      assert is_nil(Emails.get_by_gmail_id("nonexistent", user.id))
    end

    test "returns nil when email belongs to different user", %{email: email} do
      other_user = insert(:user)
      assert is_nil(Emails.get_by_gmail_id(email.gmail_id, other_user.id))
    end
  end

  describe "category_counts/1" do
    setup(%{user: user}) do
      category = insert(:category, user: user)

      %{category: category, user: user}
    end

    test "returns count of unarchived emails per category", %{
      user: user,
      category: category
    } do
      gmail_account = insert(:gmail_account, user: user)
      # Create some categorized emails
      for _ <- 1..3 do
        insert(:email, user: user, category: category, archived: false, gmail_account: gmail_account)
      end

      # Create an archived email in the same category (shouldn't be counted)
      insert(:email, user: user, category: category, archived: true, gmail_account: gmail_account)

      # Create an email in a different category
      other_category = insert(:category, user: user)
      insert(:email, user: user, category: other_category, archived: false, gmail_account: gmail_account)

      counts = Emails.category_counts(user.id)

      assert map_size(counts) == 2
      assert counts[category.id] == 3
      assert counts[other_category.id] == 1
    end

    test "only counts emails from enabled Gmail accounts", %{user: user, category: category} do
      disabled_account = insert(:gmail_account, user: user, sync_enabled: false)

      # Create emails for disabled account
      insert(:email, user: user, category: category, gmail_account: disabled_account)

      counts = Emails.category_counts(user.id)
      assert map_size(counts) == 0
    end
  end
end
