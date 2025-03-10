defmodule MailSageWeb.CategoryLive do
  @moduledoc false
  use MailSageWeb, :live_view

  alias MailSage.Categories
  alias MailSage.Categories.Category
  alias MailSage.Emails

  @records_per_page 10

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, 1)
     |> assign(:per_page, @records_per_page)
     |> assign(:form, to_form(Categories.change_category(%Category{})))}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _, socket) do
    {:noreply, apply_action(socket, params, socket.assigns.live_action)}
  end

  defp apply_action(socket, _params, :new) do
    assign(socket, :page_title, "New Category")
  end

  defp apply_action(socket, %{"id" => category_id} = params, live_action) when live_action in [:show, :edit] do
    category = Categories.get_user_category(socket.assigns.current_user.id, category_id)

    page =
      params
      |> Map.get("page", "1")
      |> String.to_integer()

    page_of_emails =
      Emails.list_emails(
        socket.assigns.current_user.id,
        category_id: category_id,
        archived: false,
        page: page,
        per_page: socket.assigns.per_page
      )

    socket
    |> assign(:page_title, category.name)
    |> assign(:category, category)
    |> assign(:page_of_emails, page_of_emails)
    |> assign(:emails, page_of_emails.entries)
    |> assign(:selected_emails, MapSet.new())
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"category" => params}, socket) do
    form =
      %Category{}
      |> Categories.change_category(params)
      |> to_form(as: "category")

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"category" => category_params}, socket) do
    category_params = Map.put(category_params, "user_id", socket.assigns.current_user.id)

    updated_socket =
      create_or_update_category(socket, category_params, socket.assigns.live_action)

    {:noreply, updated_socket}
  end

  def handle_event("toggle_email", %{"id" => id}, socket) do
    selected = socket.assigns.selected_emails
    email_id = String.to_integer(id)

    selected =
      if email_id in selected do
        MapSet.delete(selected, email_id)
      else
        MapSet.put(selected, email_id)
      end

    {:noreply, assign(socket, :selected_emails, selected)}
  end

  def handle_event("toggle_all", _params, socket) do
    selected = socket.assigns.selected_emails
    emails = socket.assigns.emails

    selected =
      if MapSet.size(selected) == length(emails) do
        MapSet.new()
      else
        MapSet.new(emails, & &1.id)
      end

    {:noreply, assign(socket, :selected_emails, selected)}
  end

  def handle_event("archive_selected", _params, socket) do
    Emails.bulk_archive_emails(MapSet.to_list(socket.assigns.selected_emails))

    {:noreply,
     socket
     |> put_flash(:info, "Selected emails have been archived")
     |> push_navigate(to: ~p"/categories/#{socket.assigns.category.id}")}
  end

  def handle_event("unsubscribe_selected", _params, socket) do
    # Schedule unsubscribe jobs for selected emails
    # This will be implemented later

    {:noreply,
     socket
     |> put_flash(:info, "Unsubscribe process started for selected emails")
     |> assign(:selected_emails, MapSet.new())}
  end

  def handle_event("edit_category", _params, socket) do
    form = to_form(Categories.change_category(socket.assigns.category))

    {:noreply,
     socket
     |> assign(:live_action, :edit)
     |> assign(:page_title, "Edit Category")
     |> assign(:form, form)}
  end

  def handle_event("delete_category", _params, socket) do
    case Categories.delete_category(socket.assigns.category) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category deleted successfully")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete category")}
    end
  end

  def handle_event("page_changed", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/categories/#{socket.assigns.category.id}?page=#{page}")}
  end

  defp create_or_update_category(socket, params, :new) do
    case Categories.create_category(params) do
      {:ok, category} ->
        socket
        |> put_flash(:info, "Category created successfully")
        |> push_navigate(to: ~p"/categories/#{category}")

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, changeset: changeset)
    end
  end

  defp create_or_update_category(socket, params, :edit) do
    case Categories.update_category(socket.assigns.category, params) do
      {:ok, category} ->
        socket
        |> put_flash(:info, "Category updated successfully")
        |> push_navigate(to: ~p"/categories/#{category}")

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, changeset: changeset)
    end
  end

  @impl Phoenix.LiveView
  def render(%{live_action: live_action} = assigns) when live_action in [:new, :edit] do
    ~H"""
    <div class="relative mx-auto max-w-2xl">
      <.header>
        New Category
      </.header>

      <.simple_form
        for={@form}
        id="category-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-8 space-y-8 bg-white"
      >
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input
          field={@form[:color]}
          type="color"
          label="Color"
          value={@form.data.color || "#4F46E5"}
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Category</.button>
        </:actions>
      </.simple_form>
      <div class="absolute bottom-0 right-0 mt-6">
        <.link
          navigate={~p"/dashboard"}
          class="sm:order-0 order-1 ml-3 inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:ml-0"
        >
          <.icon name="hero-arrow-left-solid" class="w-4 h-4 inline" /> Back to dashboard
        </.link>
      </div>
    </div>
    """
  end

  def render(%{category: category} = assigns) when not is_nil(category) do
    ~H"""
    <div>
      <div class="mb-8 sm:flex sm:items-center sm:justify-between">
        <div>
          <h1 class="text-base font-semibold leading-6 text-gray-900">
            {@category.name}
            <span class="ml-2 inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700">
              {length(@emails)} emails
            </span>
          </h1>
          <p class="mt-2 italic text-sm text-gray-700">{@category.description}</p>
        </div>
        <div class="mt-4 flex sm:ml-4 sm:mt-0">
          <button
            type="button"
            phx-click="edit_category"
            class="sm:order-0 order-1 ml-3 inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:ml-0"
          >
            Edit Category
          </button>
          <button
            type="button"
            phx-click="delete_category"
            data-confirm="Are you sure you want to delete this category?"
            class="order-0 inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 sm:order-1 sm:ml-3"
          >
            Delete Category
          </button>
        </div>
      </div>
      <div :if={length(@emails) > 0} class="mt-4 bg-white shadow sm:rounded-lg">
        <div class="p-4 sm:p-6">
          <div class="sm:flex sm:items-center">
            <div class="sm:flex-auto">
              <h2 class="text-base font-semibold leading-6 text-gray-900">Emails</h2>
              <p class="mt-2 text-sm text-gray-700">
                A list of all emails in this category that haven't been archived.
              </p>
            </div>
            <div class="mt-4 sm:ml-16 sm:mt-0 sm:flex-none">
              <div class="flex space-x-3">
                <button
                  :if={@selected_emails != MapSet.new()}
                  type="button"
                  phx-click="archive_selected"
                  class="inline-flex items-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
                >
                  Archive Selected
                </button>
                <button
                  :if={@selected_emails != MapSet.new()}
                  type="button"
                  phx-click="unsubscribe_selected"
                  class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                >
                  Unsubscribe Selected
                </button>
              </div>
            </div>
          </div>

          <div :if={length(@emails) > 0} class="mt-8 flow-root">
            <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
              <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
                <table class="min-w-full divide-y divide-gray-300">
                  <thead>
                    <tr>
                      <th scope="col" class="relative px-7 sm:w-12 sm:px-6">
                        <input
                          type="checkbox"
                          class="absolute left-4 top-1/2 -mt-2 h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                          phx-click="toggle_all"
                          checked={
                            length(@emails) > 0 && MapSet.size(@selected_emails) == length(@emails)
                          }
                        />
                      </th>
                      <th
                        scope="col"
                        class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-0"
                      >
                        From
                      </th>
                      <th
                        scope="col"
                        class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900"
                      >
                        Account
                      </th>
                      <th
                        scope="col"
                        class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900"
                      >
                        Subject
                      </th>
                      <th
                        scope="col"
                        class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900"
                      >
                        Summary
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-200">
                    <%= for email <- @emails do %>
                      <tr
                        class="group hover:bg-gray-50 cursor-pointer"
                        phx-click={JS.navigate(~p"/emails/#{email.id}")}
                      >
                        <td class="relative px-7 sm:w-12 sm:px-6">
                          <input
                            type="checkbox"
                            class="absolute left-4 top-1/2 -mt-2 h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                            phx-click="toggle_email"
                            phx-value-id={email.id}
                            checked={email.id in @selected_emails}
                          />
                        </td>
                        <td
                          class="max-w-[8rem] md:max-w-[12rem] break-words py-4 pl-4 pr-3 text-sm text-gray-500 sm:pl-0"
                          title={email.from}
                        >
                          {email.from}
                        </td>
                        <td class="px-3 py-4 text-sm text-gray-500">
                          {email.gmail_account.email}
                        </td>
                        <td class="px-3 py-4 text-sm text-gray-500">
                          {email.subject}
                        </td>
                        <td class="px-3 py-4 text-sm text-gray-500">
                          {email.ai_summary}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>
      <div class="mt-6">
        <.link
          navigate={~p"/dashboard"}
          class="sm:order-0 order-1 ml-3 inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:ml-0"
        >
          <.icon name="hero-arrow-left-solid" class="w-4 h-4 inline" /> Back to dashboard
        </.link>
      </div>
    </div>
    <div class="mt-4 flex items-center justify-between border-t border-gray-200 bg-white px-4 py-3 sm:px-6">
      <div class="flex flex-1 justify-between sm:hidden">
        <button
          :if={@page_of_emails.page_number > 1}
          phx-click="page_changed"
          phx-value-page={@page_of_emails.page_number - 1}
          class="relative inline-flex items-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          Previous
        </button>
        <button
          :if={@page_of_emails.page_number < @page_of_emails.total_pages}
          phx-click="page_changed"
          phx-value-page={@page_of_emails.page_number + 1}
          class="relative ml-3 inline-flex items-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          Next
        </button>
      </div>
      <div class="hidden sm:flex sm:flex-1 sm:items-center sm:justify-between">
        <div>
          <p class="text-sm text-gray-700">
            Showing
            <span class="font-medium">
              {(@page_of_emails.page_number - 1) * @page_of_emails.page_size + 1}
            </span>
            to
            <span class="font-medium">
              {min(
                @page_of_emails.page_number * @page_of_emails.page_size,
                @page_of_emails.total_entries
              )}
            </span>
            of <span class="font-medium">{@page_of_emails.total_entries}</span>
            results
          </p>
        </div>
        <div>
          <nav class="isolate inline-flex -space-x-px rounded-md shadow-sm" aria-label="Pagination">
            <button
              :if={@page_of_emails.page_number > 1}
              phx-click="page_changed"
              phx-value-page={@page_of_emails.page_number - 1}
              class="relative inline-flex items-center rounded-l-md px-2 py-2 text-gray-400 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:z-20 focus:outline-offset-0"
            >
              <span class="sr-only">Previous</span>
              <.icon name="hero-chevron-left-solid" class="h-5 w-5" />
            </button>

            <%= for page <- 1..@page_of_emails.total_pages do %>
              <button
                phx-click="page_changed"
                phx-value-page={page}
                class={[
                  "relative inline-flex items-center px-4 py-2 text-sm font-semibold",
                  if(page == @page_of_emails.page_number,
                    do:
                      "z-10 bg-indigo-600 text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600",
                    else:
                      "text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:outline-offset-0"
                  )
                ]}
              >
                {page}
              </button>
            <% end %>

            <button
              :if={@page_of_emails.page_number < @page_of_emails.total_pages}
              phx-click="page_changed"
              phx-value-page={@page_of_emails.page_number + 1}
              class="relative inline-flex items-center rounded-r-md px-2 py-2 text-gray-400 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:z-20 focus:outline-offset-0"
            >
              <span class="sr-only">Next</span>
              <.icon name="hero-chevron-right-solid" class="h-5 w-5" />
            </button>
          </nav>
        </div>
      </div>
    </div>
    """
  end
end
