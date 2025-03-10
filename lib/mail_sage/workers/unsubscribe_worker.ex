# defmodule MailSage.Workers.UnsubscribeWorker do
#   @moduledoc """
#   Background worker for handling email unsubscribe operations.
#   """

#   # TODO: Use Task.Supervisor instead of Oban

#   use Oban.Worker, queue: :unsubscribe

#   alias MailSage.Emails
#   # alias MailSage.Services.Gmail

#   @impl Oban.Worker
#   def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
#     with {:ok, email} <- fetch_email(email_id),
#          {:ok, user} <- fetch_user(email.user_id),
#          {:ok, _} <- process_unsubscribe(email, user) do
#       :ok
#     end
#   end

#   def schedule_unsubscribe(email_id) do
#     %{email_id: email_id}
#     |> new()
#     |> Oban.insert()
#   end

#   defp fetch_email(email_id) do
#     case Emails.get_email!(email_id) do
#       nil -> {:error, :email_not_found}
#       email -> {:ok, email}
#     end
#   end

#   defp fetch_user(user_id) do
#     case MailSage.Accounts.get_user(user_id) do
#       nil -> {:error, :user_not_found}
#       user -> {:ok, user}
#     end
#   end

#   defp process_unsubscribe(email, user) do
#     cond do
#       is_nil(email.unsubscribe_link) ->
#         {:error, :no_unsubscribe_link}

#       String.contains?(email.unsubscribe_link, "mailto:") ->
#         process_mailto_unsubscribe(email, user)

#       true ->
#         process_http_unsubscribe(email, user)
#     end
#   end

#   defp process_mailto_unsubscribe(email, user) do
#     [_, email_address] = Regex.run(~r/mailto:(.+)/, email.unsubscribe_link)

#     # Extract subject and body if present in the mailto link
#     subject =
#       case Regex.run(~r/subject=([^&]+)/, email.unsubscribe_link) do
#         [_, subject] -> URI.decode(subject)
#         nil -> "Unsubscribe"
#       end

#     body =
#       case Regex.run(~r/body=([^&]+)/, email.unsubscribe_link) do
#         [_, body] -> URI.decode(body)
#         nil -> "Please unsubscribe me from this mailing list."
#       end

#     # Use Gmail API to send unsubscribe email
#     with {:ok, conn} <- MailSage.Auth.Google.get_gmail_conn(user) do
#       message = %{
#         raw:
#           Base.url_encode64("""
#           From: #{user.email}
#           To: #{email_address}
#           Subject: #{subject}

#           #{body}
#           """)
#       }

#       GoogleApi.Gmail.V1.Api.Accounts.gmail_users_messages_send(
#         conn,
#         "me",
#         body: message
#       )
#     end
#   end

#   defp process_http_unsubscribe(email, user) do
#     # Make HTTP request to unsubscribe link using Finch
#     request = Finch.build(:get, email.unsubscribe_link)

#     case Finch.request(request, MailSage.Finch) do
#       {:ok, %Finch.Response{status: status}} when status in 200..299 ->
#         {:ok, :unsubscribed}

#       {:ok, %Finch.Response{status: 302, headers: headers}} ->
#         # Follow redirect if present
#         case List.keyfind(headers, "location", 0) do
#           {"location", location} ->
#             process_http_unsubscribe(%{email | unsubscribe_link: location}, user)

#           nil ->
#             {:error, :invalid_redirect}
#         end

#       _ ->
#         {:error, :unsubscribe_failed}
#     end
#   end
# end
