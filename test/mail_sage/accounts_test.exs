defmodule MailSage.AccountsTest do
  use MailSage.DataCase, async: true

  alias MailSage.Accounts
  alias MailSage.Accounts.GmailAccount
  alias MailSage.Accounts.User

  @valid_user_attrs %{
    email: "test@example.com",
    name: "Test User",
    picture: "https://example.com/picture.jpg",
    access_token: "valid_token",
    google_refresh_token: "refresh_token",
    token_expires_at: DateTime.add(DateTime.utc_now(), 3600)
  }

  @valid_gmail_attrs %{
    email: "gmail@example.com",
    google_refresh_token: "refresh_token",
    is_primary: true,
    last_sync_at: DateTime.utc_now(),
    sync_enabled: true
  }

  describe "get_user/1" do
    test "returns user when user exists" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      assert Accounts.get_user(user.id) == user
    end

    test "returns nil when user doesn't exist" do
      assert Accounts.get_user(0) == nil
    end

    test "raises an error when id is nil" do
      assert_raise ArgumentError, fn ->
        Accounts.get_user(nil)
      end
    end

    test "raises an error when id is invalid format" do
      assert_raise Ecto.Query.CastError, fn ->
        Accounts.get_user("invalid")
      end
    end
  end

  describe "get_user_by_email/1" do
    test "returns user when email exists" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      assert Accounts.get_user_by_email(user.email) == user
    end

    test "returns nil when email doesn't exist" do
      assert Accounts.get_user_by_email("nonexistent@example.com") == nil
    end

    test "returns nil when email is nil" do
      assert_raise FunctionClauseError, fn ->
        Accounts.get_user_by_email(nil)
      end
    end

    test "is case sensitive" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      assert Accounts.get_user_by_email(user.email) == user
      refute Accounts.get_user_by_email(String.upcase(user.email)) == user
    end
  end

  describe "create_user/1" do
    test "creates user with valid attributes" do
      assert {:ok, %User{}} = Accounts.create_user(@valid_user_attrs)
    end

    test "fails with invalid email" do
      attrs = %{@valid_user_attrs | email: "invalid"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "has invalid format" in errors_on(changeset).email
    end

    test "fails with duplicate email" do
      {:ok, _user} = Accounts.create_user(@valid_user_attrs)
      assert {:error, changeset} = Accounts.create_user(@valid_user_attrs)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Accounts.create_user(%{})
      assert "can't be blank" in errors_on(changeset).email
      assert "can't be blank" in errors_on(changeset).google_refresh_token
    end
  end

  describe "update_user_tokens/2" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      %{user: user}
    end

    test "updates tokens with valid attributes", %{user: user} do
      update_attrs = %{
        google_token: "updated_google_token",
        google_refresh_token: "new_refresh_token"
      }

      assert {:ok, updated_user} = Accounts.update_user_tokens(user, update_attrs)
      assert updated_user.google_token == "updated_google_token"
      assert updated_user.google_refresh_token == "new_refresh_token"
    end

    test "partial token update is allowed", %{user: user} do
      assert {:ok, updated_user} = Accounts.update_user_tokens(user, %{google_token: "new_token"})
      assert updated_user.google_token == "new_token"
      assert updated_user.google_refresh_token == user.google_refresh_token
    end

    test "fails with invalid token data", %{user: user} do
      assert {:error, changeset} = Accounts.update_user_tokens(user, %{google_token: nil})
      assert "can't be blank" in errors_on(changeset).google_token
    end
  end

  describe "token_expired?/1" do
    test "returns true for expired token" do
      user = %User{token_expires_at: DateTime.add(DateTime.utc_now(), -3600)}
      assert Accounts.token_expired?(user) == true
    end

    test "returns false for valid token" do
      user = %User{token_expires_at: DateTime.add(DateTime.utc_now(), 3600)}
      assert Accounts.token_expired?(user) == false
    end

    test "returns true for nil expiry" do
      user = %User{token_expires_at: nil}
      assert Accounts.token_expired?(user) == true
    end

    test "returns true for token expiring exactly now" do
      user = %User{token_expires_at: DateTime.utc_now()}
      assert Accounts.token_expired?(user) == true
    end
  end

  describe "list_gmail_accounts/1" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      {:ok, other_user} = Accounts.create_user(%{@valid_user_attrs | email: "other@example.com"})
      %{user: user, other_user: other_user}
    end

    test "returns empty list when user has no accounts", %{user: user} do
      assert Accounts.list_gmail_accounts(user.id) == []
    end

    test "returns all gmail accounts for user", %{user: user} do
      attrs1 = Map.merge(@valid_gmail_attrs, %{user_id: user.id, email: "one@gmail.com"})
      attrs2 = Map.merge(@valid_gmail_attrs, %{user_id: user.id, email: "two@gmail.com"})

      {:ok, account1} = Accounts.create_gmail_account(attrs1)
      {:ok, account2} = Accounts.create_gmail_account(attrs2)

      accounts = Accounts.list_gmail_accounts(user.id)
      assert length(accounts) == 2
      assert Enum.map(accounts, & &1.id) == [account1.id, account2.id]
    end

    test "orders by primary status and insertion time", %{user: user} do
      attrs1 = Map.merge(@valid_gmail_attrs, %{user_id: user.id, is_primary: false})

      attrs2 =
        @valid_gmail_attrs
        |> Map.merge(%{user_id: user.id, is_primary: true})
        |> Map.put(:email, "gmail+1@example.com")

      {:ok, non_primary} = Accounts.create_gmail_account(attrs1)
      {:ok, primary} = Accounts.create_gmail_account(attrs2)

      [first, second] = Accounts.list_gmail_accounts(user.id)
      assert first.id == primary.id
      assert second.id == non_primary.id
    end

    test "doesn't return other users' accounts", %{user: user, other_user: other_user} do
      attrs = Map.put(@valid_gmail_attrs, :user_id, other_user.id)
      {:ok, _other_account} = Accounts.create_gmail_account(attrs)

      assert Accounts.list_gmail_accounts(user.id) == []
    end
  end

  describe "get_gmail_account!/1" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      attrs = Map.put(@valid_gmail_attrs, :user_id, user.id)
      {:ok, account} = Accounts.create_gmail_account(attrs)
      %{user: user, account: account}
    end

    test "returns gmail account when exists", %{account: account} do
      assert Accounts.get_gmail_account!(account.id) == account
    end

    test "raises when account doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_gmail_account!(0)
      end
    end

    test "raises an error when id is nil" do
      assert_raise ArgumentError, fn ->
        Accounts.get_gmail_account!(nil)
      end
    end
  end

  describe "create_gmail_account/1" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      %{user: user}
    end

    test "creates account with valid attributes", %{user: user} do
      attrs = Map.put(@valid_gmail_attrs, :user_id, user.id)
      assert {:ok, %GmailAccount{} = account} = Accounts.create_gmail_account(attrs)
      assert account.email == attrs.email
      assert account.is_primary == attrs.is_primary
      assert account.sync_enabled == attrs.sync_enabled
      assert account.user_id == user.id
    end

    test "fails with missing user_id" do
      assert {:error, changeset} = Accounts.create_gmail_account(@valid_gmail_attrs)
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "fails with invalid email" do
      attrs = %{@valid_gmail_attrs | email: "invalid"}
      assert {:error, changeset} = Accounts.create_gmail_account(attrs)
      assert "has invalid format" in errors_on(changeset).email
    end

    test "fails with duplicate email for same user", %{user: user} do
      attrs = Map.put(@valid_gmail_attrs, :user_id, user.id)
      {:ok, _account} = Accounts.create_gmail_account(attrs)
      assert {:error, changeset} = Accounts.create_gmail_account(attrs)
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "update_gmail_account/2" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      attrs = Map.put(@valid_gmail_attrs, :user_id, user.id)
      {:ok, account} = Accounts.create_gmail_account(attrs)
      %{user: user, account: account}
    end

    test "updates account with valid attributes", %{account: account} do
      update_attrs = %{
        sync_enabled: false,
        google_refresh_token: "new_token"
      }

      assert {:ok, updated} = Accounts.update_gmail_account(account, update_attrs)
      assert updated.sync_enabled == false
      assert updated.google_refresh_token == "new_token"
    end

    test "partial update is allowed", %{account: account} do
      assert {:ok, updated} = Accounts.update_gmail_account(account, %{sync_enabled: false})
      assert updated.sync_enabled == false
      assert updated.email == account.email
      assert updated.is_primary == account.is_primary
    end

    test "fails with invalid email", %{account: account} do
      assert {:error, changeset} = Accounts.update_gmail_account(account, %{email: "invalid"})
      assert "has invalid format" in errors_on(changeset).email
    end
  end
end
