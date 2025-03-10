defmodule MailSage.Emails.Email do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "emails" do
    field :gmail_id, :string
    field :thread_id, :string
    field :subject, :string
    field :from, :string
    field :to, {:array, :string}
    field :cc, {:array, :string}
    field :bcc, {:array, :string}
    field :date, :utc_datetime
    field :snippet, :string
    field :body_html, :string
    field :body_text, :string
    field :ai_summary, :string
    field :labels, {:array, :string}
    field :unsubscribe_link, :string
    field :archived, :boolean, default: false

    belongs_to :user, MailSage.Accounts.User
    belongs_to :gmail_account, MailSage.Accounts.GmailAccount
    belongs_to :category, MailSage.Categories.Category

    timestamps()
  end

  @doc """
  Creates a changeset for the Email schema.
  """
  def changeset(email, attrs) do
    email
    |> cast(attrs, [
      :gmail_id,
      :thread_id,
      :subject,
      :from,
      :to,
      :cc,
      :bcc,
      :date,
      :snippet,
      :body_html,
      :body_text,
      :ai_summary,
      :labels,
      :unsubscribe_link,
      :archived,
      :user_id,
      :gmail_account_id,
      :category_id
    ])
    |> validate_required([:gmail_id, :user_id, :gmail_account_id])
    |> validate_length(:subject, max: 1000)
    |> validate_length(:from, max: 255)
    |> validate_array_length(:to, max: 100)
    |> validate_array_length(:cc, max: 100)
    |> validate_array_length(:bcc, max: 100)
    |> validate_array_length(:labels, max: 50)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:gmail_account_id)
    |> foreign_key_constraint(:category_id)
    |> unique_constraint([:gmail_id, :gmail_account_id])
  end

  @doc """
  Creates a changeset for updating email categorization.
  """
  def categorize_changeset(email, attrs) do
    email
    |> cast(attrs, [:category_id])
    |> foreign_key_constraint(:category_id)
  end

  @doc """
  Creates a changeset for updating email archive status.
  """
  def archive_changeset(email, archived) do
    email
    |> cast(%{archived: archived}, [:archived])
    |> validate_required([:archived])
  end

  defp validate_array_length(changeset, field, opts) do
    case get_change(changeset, field) do
      nil ->
        changeset

      value when is_list(value) ->
        case Keyword.get(opts, :max) do
          nil ->
            changeset

          max when length(value) > max ->
            add_error(changeset, field, "has too many items (maximum is #{max})")

          _ ->
            changeset
        end

      _ ->
        add_error(changeset, field, "must be a list")
    end
  end
end
