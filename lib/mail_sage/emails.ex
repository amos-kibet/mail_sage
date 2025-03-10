defmodule MailSage.Emails do
  @moduledoc """
  The Emails context handles email management and categorization.
  """

  import Ecto.Query, warn: false

  alias MailSage.Emails.Email
  alias MailSage.Repo
  alias MailSage.Services.Gmail

  require Logger

  @doc """
  Returns a list of emails for a user, optionally filtered by category.
  """
  def list_emails(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)

    Email
    |> where(user_id: ^user_id)
    |> filter_by_category(opts[:category_id])
    |> filter_by_archived(opts[:archived])
    |> order_by(desc: :date)
    |> preload(:gmail_account)
    |> Repo.paginate(page: page, page_size: per_page)
  end

  @doc """
  Gets a single email for a specific user.
  Returns nil if the email does not exist or doesn't belong to the user.
  """
  def get_user_email(user_id, email_id) do
    Email
    |> where(user_id: ^user_id, id: ^email_id)
    |> preload([:category, :gmail_account])
    |> Repo.one()
  end

  @doc """
  Creates an email.
  """
  def create_email(attrs \\ %{}) do
    %Email{}
    |> Email.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an email.
  """
  def update_email(%Email{} = email, attrs) do
    email
    |> Email.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Categorizes an email.
  """
  def categorize_email(%Email{} = email, category_id) do
    email
    |> Email.categorize_changeset(%{category_id: category_id})
    |> Repo.update()
  end

  @doc """
  Archives or unarchives an email.
  """
  def archive_email(%Email{} = email, archive \\ true) do
    with {:ok, _} <- update_gmail_archive_status(email, archive) do
      do_archive_email(email, archive)
    end
  end

  @doc """
  Bulk archives emails.
  """
  def bulk_archive_emails(email_ids, archived \\ true) when is_list(email_ids) do
    emails = Repo.all(from e in Email, where: e.id in ^email_ids, preload: :user)

    # Archive in Gmail first
    Enum.each(emails, &update_gmail_archive_status(&1, archived))

    # Then update local database
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Email
    |> where([e], e.id in ^email_ids)
    |> Repo.update_all(set: [archived: archived, updated_at: now])
  end

  @doc """
  Bulk categorize emails.
  """
  def bulk_categorize_emails(email_ids, category_id) when is_list(email_ids) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Email
    |> where([e], e.id in ^email_ids)
    |> Repo.update_all(set: [category_id: category_id, updated_at: now])
  end

  @doc """
  Gets an email by Gmail ID and user ID.
  """
  def get_by_gmail_id(gmail_id, user_id) do
    Repo.get_by(Email, gmail_id: gmail_id, user_id: user_id)
  end

  @doc """
  Returns the count of unarchived emails in each category for a user across all Gmail accounts.
  """
  def category_counts(user_id) do
    Email
    |> where(user_id: ^user_id, archived: false)
    |> join(:inner, [e], g in assoc(e, :gmail_account), as: :gmail_account)
    |> where([e, gmail_account: g], g.sync_enabled == true)
    |> group_by(:category_id)
    |> select([e], {e.category_id, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  # TODO: Test if this is working
  # def process_unsubscribe(%Email{} = email, _user) do
  #   MailSage.Unsubscribe.Queue.enqueue(email)
  #   {:ok, :unsubscribe_queued}
  # end

  @doc """
  Process a single email unsubscribe request.
  Returns {:ok, email} on success, {:error, reason} on failure.
  """
  def process_unsubscribe(%Email{} = email, _user) do
    case find_unsubscribe_link(email) do
      {:ok, link} ->
        # Make the HTTP request to the unsubscribe link using Finch
        request = Finch.build(:get, link)

        case Finch.request(request, MailSage.Finch) do
          {:ok, %{status: status}} when status in 200..299 ->
            # Mark the email as unsubscribed in our database
            update_email(email, %{unsubscribed: true})

          {:ok, response} ->
            Logger.error("Unexpected response for unsubscribe #{email.id}: #{inspect(response)}")
            {:error, :invalid_response}

          {:error, reason} ->
            Logger.error("Failed to unsubscribe email #{email.id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :no_link_found} ->
        Logger.warning("No unsubscribe link found for email #{email.id}")
        {:error, :no_unsubscribe_link}
    end
  end

  @unsubscribe_keywords [
    "unsubscribe",
    "opt out",
    "email preferences",
    "subscription preferences",
    "manage subscriptions",
    "stop receiving",
    "remove from list"
  ]

  @doc """
  Finds the most likely unsubscribe link in an email by:
  1. Checking List-Unsubscribe header
  2. Scanning HTML for links near unsubscribe-related text
  3. Looking for common unsubscribe URL patterns
  """
  def find_unsubscribe_link(%Email{} = email) do
    # First try the List-Unsubscribe header if it exists
    with {:error, :no_header} <- extract_list_unsubscribe_link(email),
         {:error, :no_link} <- find_link_near_unsubscribe_text(email),
         {:error, :no_link} <- find_common_unsubscribe_patterns(email) do
      {:error, :no_link_found}
    end
  end

  # Try to extract from List-Unsubscribe header first
  defp extract_list_unsubscribe_link(%{headers: %{"list-unsubscribe" => value}}) when is_binary(value) do
    case Regex.run(~r/<(https?:\/\/[^>]+)>/, value) do
      [_, url] -> {:ok, url}
      _ -> {:error, :no_header}
    end
  end

  defp extract_list_unsubscribe_link(_), do: {:error, :no_header}

  # Look for links near unsubscribe-related text in HTML
  defp find_link_near_unsubscribe_text(%Email{body_html: html}) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> find_unsubscribe_links()
        |> get_best_unsubscribe_link()

      _ ->
        {:error, :no_link}
    end
  end

  defp find_link_near_unsubscribe_text(_), do: {:error, :no_link}

  defp find_unsubscribe_links(document) do
    Enum.flat_map(@unsubscribe_keywords, fn keyword ->
      # Find text nodes containing our keywords
      text_nodes = Floki.find(document, ":fl-contains('#{keyword}')")

      Enum.flat_map(text_nodes, fn node ->
        # Look for links in the parent elements and siblings
        parent = Floki.find(node, "parent::*")
        siblings = Floki.find(node, "following-sibling::*[position()<=2]")

        (parent ++ siblings)
        |> Floki.find("a[href]")
        |> Enum.map(fn link ->
          {link, keyword, compute_link_score(link, keyword)}
        end)
      end)
    end)
  end

  # Compute a relevance score for the link based on various factors
  defp compute_link_score(link, keyword) do
    href = link |> Floki.attribute("href") |> List.first() || ""
    text = link |> Floki.text() |> String.downcase()

    # Start with a base score
    base_score = 1

    # Add points for various factors
    keyword_in_text = if String.contains?(text, keyword), do: 3, else: 0
    keyword_in_href = if String.contains?(href, keyword), do: 2, else: 0

    common_path =
      if String.contains?(href, ["unsubscribe", "opt-out", "preferences"]), do: 2, else: 0

    base_score + keyword_in_text + keyword_in_href + common_path
  end

  # Get the link with the highest relevance score
  defp get_best_unsubscribe_link([]), do: {:error, :no_link}

  defp get_best_unsubscribe_link(scored_links) do
    {link, _keyword, _score} =
      Enum.max_by(scored_links, fn {_link, _keyword, score} -> score end)

    case Floki.attribute(link, "href") do
      [url | _] -> {:ok, url}
      _ -> {:error, :no_link}
    end
  end

  # Look for common unsubscribe URL patterns in the HTML
  defp find_common_unsubscribe_patterns(%Email{body_html: html}) when is_binary(html) do
    patterns = [
      ~r/href=["'](https?:\/\/[^"']+(?:unsubscribe|opt-out|preferences)[^"']*)/i,
      ~r/href=["'](https?:\/\/[^"']+(?:subscription|mailing-list)[^"']*(?:remove|stop)[^"']*)/i
    ]

    Enum.find_value(patterns, {:error, :no_link}, fn pattern ->
      case Regex.run(pattern, html) do
        [_, url] -> {:ok, url}
        _ -> false
      end
    end)
  end

  defp find_common_unsubscribe_patterns(_), do: {:error, :no_link}

  defp filter_by_category(query, nil), do: query

  defp filter_by_category(query, category_id) do
    where(query, [e], e.category_id == ^category_id)
  end

  defp filter_by_archived(query, nil), do: query

  defp filter_by_archived(query, archived) do
    where(query, [e], e.archived == ^archived)
  end

  defp do_archive_email(email, archive) do
    email
    |> Email.archive_changeset(archive)
    |> Repo.update()
  end

  defp update_gmail_archive_status(email, archive) do
    email = Repo.preload(email, :user)

    if archive do
      Gmail.archive_email(email.user, email.gmail_id)
    else
      Gmail.unarchive_email(email.user, email.gmail_id)
    end
  end
end
