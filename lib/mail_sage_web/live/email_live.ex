defmodule MailSageWeb.EmailLive do
  @moduledoc false
  use MailSageWeb, :live_view

  alias MailSage.Categories
  alias MailSage.Emails

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    email = Emails.get_user_email(socket.assigns.current_user.id, id)
    categories = Categories.list_categories(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(:page_title, email.subject)
     |> assign(:email, email)
     |> assign(:categories, categories)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-8 sm:flex sm:items-center sm:justify-between">
        <div>
          <h1 class="text-xl font-semibold text-gray-900">
            {@email.subject}
          </h1>
          <div class="mt-1 flex flex-col sm:mt-0 sm:flex-row sm:flex-wrap sm:space-x-6">
            <div class="mt-2 flex items-center text-sm text-gray-500">
              <.icon name="hero-envelope" class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-400" />
              From: {@email.from}
            </div>
            <div class="mt-2 flex items-center text-sm text-gray-500">
              <.icon name="hero-at-symbol" class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-400" />
              Account: {@email.gmail_account.email}
            </div>
            <%!-- <div class="mt-2 flex items-center text-sm text-gray-500">
              <.icon name="hero-calendar" class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-400" />
              {Calendar.strftime(@email.date, "%B %d, %Y at %H:%M")}
            </div> --%>
            <%= if @email.category do %>
              <div class="mt-2 flex items-center text-sm text-gray-500">
                <.icon name="hero-tag" class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-400" />
                Category: {@email.category.name}
              </div>
            <% end %>
          </div>
        </div>
        <div class="mt-4 flex sm:ml-4 sm:mt-0">
          <%!-- <div class="flex items-center">
            <.form for={%{}} as={:email} phx-submit="recategorize" class="flex items-center space-x-3">
              <select
                name="category_id"
                class="rounded-md border-0 py-1.5 pl-3 pr-10 text-gray-900 ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-indigo-600 sm:text-sm sm:leading-6"
              >
                <option value="">No Category</option>
                <%= for category <- @categories do %>
                  <option value={category.id} selected={@email.category_id == category.id}>
                    {category.name}
                  </option>
                <% end %>
              </select>
              <.button type="submit">Move</.button>
            </.form>
          </div> --%>

          <div class="ml-3">
            <button
              type="button"
              phx-click={if @email.archived, do: "unarchive", else: "archive"}
              class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
            >
              {if @email.archived, do: "Unarchive", else: "Archive"}
            </button>
          </div>

          <%= if @email.unsubscribe_link do %>
            <div class="ml-3">
              <button
                type="button"
                phx-click="unsubscribe"
                class="inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500"
              >
                Unsubscribe
              </button>
            </div>
          <% end %>
        </div>
      </div>

      <div class="overflow-hidden bg-white shadow sm:rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <div class="space-y-6">
            <div>
              <h3 class="text-sm font-medium text-gray-900">AI Summary</h3>
              <p class="mt-2 text-sm text-gray-500">{@email.ai_summary}</p>
            </div>

            <div class="border-t border-gray-200 pt-6">
              <h3 class="text-sm font-medium text-gray-900">Recipients</h3>
              <dl class="mt-2 divide-y divide-gray-200">
                <div class="flex justify-between py-2">
                  <dt class="text-sm font-medium text-gray-500">To:</dt>
                  <dd class="text-sm text-gray-900">{Enum.join(@email.to, ", ")}</dd>
                </div>
                <%= if @email.cc != [] do %>
                  <div class="flex justify-between py-2">
                    <dt class="text-sm font-medium text-gray-500">CC:</dt>
                    <dd class="text-sm text-gray-900">{Enum.join(@email.cc, ", ")}</dd>
                  </div>
                <% end %>
                <%= if @email.bcc != [] do %>
                  <div class="flex justify-between py-2">
                    <dt class="text-sm font-medium text-gray-500">BCC:</dt>
                    <dd class="text-sm text-gray-900">{Enum.join(@email.bcc, ", ")}</dd>
                  </div>
                <% end %>
              </dl>
            </div>

            <div class="border-t border-gray-200 pt-6">
              <h3 class="text-sm font-medium text-gray-900">Content</h3>
              <div class="prose prose-sm mt-2 max-w-none">
                <%= if @email.body_html do %>
                  <div id="email-content" class="mt-2" phx-update="ignore">
                    {raw(sanitize_html(@email.body_html))}
                  </div>
                <% else %>
                  <pre class="whitespace-pre-wrap"><%= @email.body_text %></pre>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("archive", _params, socket) do
    case Emails.archive_email(socket.assigns.email) do
      {:ok, email} ->
        {:noreply,
         socket
         |> assign(:email, email)
         |> put_flash(:info, "Email archived successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to archive email")}
    end
  end

  def handle_event("unarchive", _params, socket) do
    case Emails.archive_email(socket.assigns.email, false) do
      {:ok, email} ->
        {:noreply,
         socket
         |> assign(:email, email)
         |> put_flash(:info, "Email unarchived successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unarchive email")}
    end
  end

  # def handle_event("recategorize", %{"category_id" => category_id}, socket) do
  #   category_id = if category_id == "", do: nil, else: String.to_integer(category_id)

  #   case Emails.categorize_email(socket.assigns.email, category_id) do
  #     {:ok, email} ->
  #       {:noreply,
  #        socket
  #        |> assign(:email, email)
  #        |> put_flash(:info, "Email categorized successfully")}

  #     {:error, _} ->
  #       {:noreply, put_flash(socket, :error, "Failed to categorize email")}
  #   end
  # end

  def handle_event("unsubscribe", _params, socket) do
    case MailSage.Workers.UnsubscribeWorker.schedule_unsubscribe(socket.assigns.email.id) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Unsubscribe process started. This may take a few moments.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to start unsubscribe process. Please try again.")}
    end
  end

  defp sanitize_html(html) do
    html
    |> HtmlSanitizeEx.basic_html()
    |> String.replace(~r/<a /, ~s(<a target="_blank" rel="noopener noreferrer" ))
  end
end
