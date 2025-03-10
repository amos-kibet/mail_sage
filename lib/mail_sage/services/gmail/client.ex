defmodule MailSage.Services.Gmail.Client do
  @moduledoc """
  Handles Gmail API operations for fetching and managing emails.
  """

  @behaviour MailSage.Services.Gmail

  alias GoogleApi.Gmail.V1.Api.Users
  alias GoogleApi.Gmail.V1.Model.BatchModifyMessagesRequest
  alias GoogleApi.Gmail.V1.Model.Message
  alias GoogleApi.Gmail.V1.Model.ModifyMessageRequest
  alias MailSage.Auth.Google
  alias MailSage.Emails
  alias MailSage.Services.Gmail

  require Logger

  @impl Gmail
  def list_new_emails(gmail_account, opts \\ []) do
    with {:ok, conn} <- Google.get_gmail_conn(gmail_account) do
      query = build_search_query(opts)

      params =
        [q: query]
        |> maybe_add_param(:maxResults, opts[:max_results])
        |> maybe_add_param(:pageToken, opts[:page_token])
        |> maybe_add_param(:labelIds, opts[:label_ids])

      case Users.gmail_users_messages_list(conn, "me", params) do
        {:ok, response} ->
          {:ok,
           %{
             messages: response.messages || [],
             next_page_token: response.nextPageToken,
             estimated_total: response.resultSizeEstimate
           }}

        error ->
          Logger.error("#{__MODULE__}.list_new_emails/2: Error listing emails in Gmail!\n#{inspect(error)}")

          error
      end
    end
  end

  @impl Gmail
  def get_email(gmail_account, message_id, opts \\ []) do
    with {:ok, conn} <- Google.get_gmail_conn(gmail_account) do
      params =
        []
        |> maybe_add_param(:format, opts[:format] || "full")
        |> maybe_add_param(:metadataHeaders, opts[:metadata_headers])

      case Users.gmail_users_messages_get(conn, "me", message_id, params) do
        {:ok, message} -> {:ok, parse_message(message)}
        error -> error
      end
    end
  end

  @impl Gmail
  def archive_email(gmail_account, message_id) do
    modify_message(gmail_account, message_id, %ModifyMessageRequest{
      removeLabelIds: ["INBOX"]
    })
  end

  @impl Gmail
  def unarchive_email(gmail_account, message_id) do
    modify_message(gmail_account, message_id, %ModifyMessageRequest{addLabelIds: ["INBOX"]})
  end

  @impl Gmail
  def bulk_modify_messages(user, message_ids, opts \\ []) do
    with {:ok, conn} <- Google.get_gmail_conn(user) do
      request = %BatchModifyMessagesRequest{
        ids: message_ids,
        addLabelIds: opts[:add_labels],
        removeLabelIds: opts[:remove_labels]
      }

      Users.gmail_users_messages_batch_modify(conn, "me", body: request)
    end
  end

  @impl Gmail
  def import_email(gmail_account, email_id) do
    with {:ok, email_data} <- get_email(gmail_account, email_id),
         email_attrs =
           Map.merge(email_data, %{
             user_id: gmail_account.user_id,
             gmail_id: email_id,
             gmail_account_id: gmail_account.id
           }),
         {:ok, email} <- Emails.create_email(email_attrs),
         {:ok, _} <- archive_email(gmail_account, email_id) do
      {:ok, email}
    end
  end

  defp modify_message(user, message_id, request) do
    with {:ok, conn} <- Google.get_gmail_conn(user) do
      Users.gmail_users_messages_modify(
        conn,
        "me",
        message_id,
        body: request
      )
    end
  end

  defp build_search_query(opts) do
    base_query = opts[:q] || "in:inbox"

    opts
    |> Enum.reduce([base_query], fn
      {:after, date}, acc -> [format_date_query("after", date) | acc]
      {:before, date}, acc -> [format_date_query("before", date) | acc]
      {:label, label}, acc -> ["label:#{label}" | acc]
      {:query, q}, acc -> [q | acc]
      # Skip :q since we already handled it
      {:q, _}, acc -> acc
      _, acc -> acc
    end)
    |> Enum.join(" ")
  end

  defp format_date_query(operator, %DateTime{} = date) do
    formatted_date = Calendar.strftime(date, "%Y/%m/%d")
    "#{operator}:#{formatted_date}"
  end

  defp parse_message(%Message{payload: payload} = message) do
    headers = Map.new(payload.headers, &{String.downcase(&1.name), &1.value})

    %{
      thread_id: message.threadId,
      subject: headers["subject"],
      from: headers["from"],
      to: parse_address_list(headers["to"]),
      cc: parse_address_list(headers["cc"]),
      bcc: parse_address_list(headers["bcc"]),
      date: parse_date(headers["date"]),
      snippet: message.snippet,
      body_html: find_body_part(payload, "text/html"),
      body_text: find_body_part(payload, "text/plain"),
      labels: message.labelIds || [],
      unsubscribe_link: extract_unsubscribe_link(headers, payload)
    }
  end

  defp parse_address_list(nil), do: []

  defp parse_address_list(addresses) when is_binary(addresses) do
    addresses
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_str) do
    case DateTime.from_iso8601(date_str) do
      {:ok, date, _} -> date
      _ -> nil
    end
  end

  defp find_body_part(%{body: %{data: data}}, _) when not is_nil(data) do
    Base.url_decode64!(data)
  end

  defp find_body_part(%{parts: parts}, content_type) when is_list(parts) do
    Enum.find_value(parts, fn part ->
      if part.mimeType == content_type do
        find_body_part(part, content_type)
      else
        find_body_part(part, content_type)
      end
    end)
  end

  defp find_body_part(_, _), do: nil

  defp extract_unsubscribe_link(headers, payload) do
    list_unsubscribe = headers["list-unsubscribe"]

    cond do
      is_binary(list_unsubscribe) ->
        extract_url_from_angle_brackets(list_unsubscribe)

      is_binary(payload.body.data) ->
        extract_unsubscribe_from_body(payload.body.data)

      true ->
        nil
    end
  end

  defp extract_url_from_angle_brackets(text) do
    case Regex.run(~r/<(https?:\/\/[^>]+)>/, text) do
      [_, url] -> url
      _ -> nil
    end
  end

  defp extract_unsubscribe_from_body(body_data) do
    decoded_body = Base.url_decode64!(body_data)

    case Regex.run(~r/href=["'](https?:\/\/[^"']+unsubscribe[^"']+)["']/, decoded_body) do
      [_, url] -> url
      _ -> nil
    end
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: [{key, value} | params]
end
