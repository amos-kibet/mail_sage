defmodule MailSage.Accounts do
  @moduledoc """
  The Users context handles user management and authentication.
  """

  import Ecto.Query, warn: false

  alias MailSage.Accounts.GmailAccount
  alias MailSage.Accounts.User
  alias MailSage.Repo

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by id.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user's Google OAuth tokens.
  """
  def update_user_tokens(user, attrs) do
    user
    |> User.token_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns true if the user's access token is expired.
  """
  def token_expired?(user) do
    case user.token_expires_at do
      nil -> true
      expires_at -> DateTime.before?(expires_at, DateTime.utc_now())
    end
  end

  @doc """
  Lists all Gmail accounts for a user.
  """
  def list_gmail_accounts(user_id) do
    GmailAccount
    |> where(user_id: ^user_id)
    |> order_by([g], desc: g.is_primary, desc: g.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a Gmail account by ID.
  Raises if the account does not exist.
  """
  def get_gmail_account!(id) do
    Repo.get!(GmailAccount, id)
  end

  @doc """
  Updates a Gmail account.
  """
  def update_gmail_account(%GmailAccount{} = gmail_account, attrs) do
    gmail_account
    |> GmailAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a Gmail account.
  """
  def create_gmail_account(attrs \\ %{}) do
    %GmailAccount{}
    |> GmailAccount.changeset(attrs)
    |> Repo.insert()
  end
end
