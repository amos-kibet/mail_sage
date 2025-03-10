# defmodule MailSage.Workers.EmailSyncWorker do
#   @moduledoc """
#   Background worker for syncing and processing emails.
#   """

#   use Oban.Worker, queue: :email_sync

#   alias MailSage.Accounts
#   alias MailSage.Services.{Gmail, AI}

#   require Logger

#   @impl Oban.Worker
#   def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
#     # Logger.info("#{__MODULE__}.perform/1: Starting email sync")
#     # Initial sync without page token
#     perform(%Oban.Job{args: %{"user_id" => user_id, "page_token" => nil}})
#   end

#   def perform(%Oban.Job{args: %{"user_id" => user_id, "page_token" => page_token}}) do
#     with {:ok, user} <-
#            fetch_user(user_id) |> IO.inspect(label: "[PERF 1]", limit: :infinity, pretty: true),
#          {:ok, %{messages: messages, next_page_token: next_page_token}} <-
#            Gmail.list_new_emails(user,
#              max_results: 2,
#              q: "is:unread in:inbox",
#              page_token: page_token
#            )
#            |> IO.inspect(label: "[PERF 2]", limit: :infinity, pretty: true) do
#       if messages && length(messages) > 0 do
#         process_emails(user, messages)
#       end

#       if next_page_token do
#         # Schedule next page fetch
#         %{user_id: user_id, page_token: next_page_token}
#         |> new()
#         |> Oban.insert()
#       else
#         # Update last sync time only when all pages are processed
#         Accounts.update_sync_settings(user, %{last_sync_at: DateTime.utc_now()})
#       end

#       :ok
#     end
#   end

#   # def perform(%Oban.Job{args: %{"user_id" => user_id, "message_id" => message_id}}) do
#   #   with {:ok, user} <- fetch_user(user_id),
#   #        {:ok, email} <- Gmail.import_email(user, message_id),
#   #        {:ok, category_id} <- AI.categorize_email(email, user_id),
#   #        {:ok, summary} <- AI.summarize_email(email) do
#   #     # Update email with AI-generated content
#   #     MailSage.Emails.update_email(email, %{
#   #       category_id: category_id,
#   #       ai_summary: summary
#   #     })
#   #   end
#   # end

#   # Schedule sync for all active users
#   def schedule_sync(user_id) do
#     # TODO: Figure this out later, but for now, use Task.Supervisor to run the sync
#     # %{user_id: user_id}
#     # |> new()
#     # |> Oban.insert()

#     Task.Supervisor.start_child(MailSage.TaskSupervisor, fn ->
#       do_perfom(%{user_id: user_id}, nil)
#     end)
#   end

#   # Schedule processing for a specific email
#   def schedule_email_processing(user_id, email) do
#     %{user_id: user_id, email_id: email.id}
#     |> new()
#     |> Oban.insert()
#   end

#   defp fetch_user(user_id) do
#     case Accounts.get_user(user_id) do
#       nil ->
#         Logger.error("#{__MODULE__}.fetch_user/1: User not found!")
#         {:error, :user_not_found}

#       user ->
#         {:ok, user}
#     end
#   end

#   defp do_perfom(%{user_id: user_id}, _), do: do_perfom(%{user_id: user_id, page_token: nil})

#   defp do_perfom(%{user_id: user_id, page_token: page_token}) do
#     with {:ok, user} <-
#            fetch_user(user_id) |> IO.inspect(label: "[PERF 1]", limit: :infinity, pretty: true),
#          {:ok, %{messages: messages, next_page_token: next_page_token}} <-
#            Gmail.list_new_emails(user,
#              max_results: 2,
#              q: "is:unread in:inbox",
#              page_token: page_token
#            )
#            |> IO.inspect(label: "[PERF 2]", limit: :infinity, pretty: true) do
#       if messages && length(messages) > 0 do
#         process_emails(user, messages)
#       end

#       if next_page_token do
#         # Schedule next page fetch
#         # %{user_id: user_id, page_token: next_page_token}
#         # |> new()
#         # |> Oban.insert()

#         do_perfom(%{user_id: user_id, page_token: next_page_token}, nil)
#       else
#         # Update last sync time only when all pages are processed
#         Accounts.update_sync_settings(user, %{last_sync_at: DateTime.utc_now()})
#       end

#       :ok
#     end
#   end

#   defp process_emails(user, messages) do
#     # Process emails in parallel but with a max concurrency of 2 to avoid overwhelming external services
#     # messages
#     # |> Task.Supervisor.async_stream_nolink(
#     #   MailSage.TaskSupervisor,
#     #   fn message ->
#     #     with {:ok, email} <- Gmail.import_email(user, message.id),
#     #          {:ok, category_id} <- AI.categorize_email(email, user.id),
#     #          {:ok, summary} <- AI.summarize_email(email) do
#     #       MailSage.Emails.update_email(email, %{
#     #         category_id: category_id,
#     #         ai_summary: summary
#     #       })
#     #     end
#     #   end,
#     #   max_concurrency: 2,
#     #   ordered: false
#     # )
#     # |> Stream.run()
#     # |> IO.inspect(label: "[PROCESS EMAILS]", limit: :infinity, pretty: true)

#     Stream.map(messages, fn message ->
#       with {:ok, email} <- Gmail.import_email(user, message.id) |> IO.inspect(label: "[IMPORT EMAIL]", limit: :infinity, pretty: true),
#            {:ok, category_id} <- AI.categorize_email(email, user.id) |> IO.inspect(label: "[CATEGORY ID]", limit: :infinity, pretty: true),
#            {:ok, summary} <- AI.summarize_email(email) |> IO.inspect(label: "[AI SUMMARY]", limit: :infinity, pretty: true) do
#         MailSage.Emails.update_email(email, %{
#           category_id: category_id,
#           ai_summary: summary
#         })
#         |> IO.inspect(label: "[UPDATE EMAIL]", limit: :infinity, pretty: true)
#       end
#     end)
#     |> Stream.run()
#     |> IO.inspect(label: "[PROCESS EMAILS]", limit: :infinity, pretty: true)
#   end
# end
