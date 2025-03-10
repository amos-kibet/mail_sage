defmodule MailSageWeb.DashboardLive do
  @moduledoc false
  use MailSageWeb, :live_view

  alias MailSage.Accounts
  alias MailSage.Categories
  alias MailSage.Emails

  require Logger

  on_mount {MailSageWeb.LiveView.Hooks.SyncHooks, :sync}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    updated_socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MailSage.PubSub, "user:#{socket.assigns.current_user.id}")

        %{id: current_user_id} = socket.assigns.current_user

        categories = Categories.list_categories(current_user_id)
        email_counts = Emails.category_counts(current_user_id)
        gmail_accounts = Accounts.list_gmail_accounts(current_user_id)

        assign(socket,
          page_title: "Dashboard",
          categories: categories,
          email_counts: email_counts,
          gmail_accounts: gmail_accounts
        )
      else
        assign(socket,
          page_title: "Dashboard",
          categories: [],
          email_counts: %{},
          gmail_accounts: []
        )
      end

    {:ok,
     assign(updated_socket,
       last_sync: updated_socket.assigns.current_user.last_sync_at,
       page_title: "Dashboard",
       syncing?: false
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("sync_now", _params, socket) do
    {:ok, _pid} = MailSage.EmailSync.schedule_sync(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(syncing?: true)
     |> put_flash(:info, "Email sync started. This may take a few minutes.")}
  end

  def handle_event("connect_gmail", _params, socket) do
    {:noreply, redirect(socket, external: MailSage.Auth.Google.authorize_url())}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_sync", %{"id" => account_id}, socket) do
    account = Accounts.get_gmail_account!(account_id)

    {:ok, _updated_account} =
      Accounts.update_gmail_account(account, %{sync_enabled: !account.sync_enabled})

    gmail_accounts = Accounts.list_gmail_accounts(socket.assigns.current_user.id)
    {:noreply, assign(socket, :gmail_accounts, gmail_accounts)}
  end

  @impl Phoenix.LiveView
  def handle_info({:sync_complete, user_id}, socket) do
    if socket.assigns.current_user.id == user_id do
      %{id: current_user_id} = socket.assigns.current_user
      categories = Categories.list_categories(current_user_id)
      email_counts = Emails.category_counts(current_user_id)
      gmail_accounts = Accounts.list_gmail_accounts(current_user_id)

      {
        :noreply,
        socket
        |> assign(syncing?: false)
        |> assign(last_sync: DateTime.utc_now())
        |> assign(categories: categories)
        |> assign(email_counts: email_counts)
        |> assign(gmail_accounts: gmail_accounts)
        #  |> put_flash(:info, "Email sync complete!")
      }
    else
      {:noreply, socket}
    end
  end

  def handle_info(info, socket) do
    Logger.warning("#{__MODULE__}.handle_info/2: Unhandled info\n#{inspect(info)}")
    {:noreply, socket}
  end

  defp format_last_sync(nil), do: "Never"
  defp format_last_sync(datetime), do: Timex.format!(datetime, "{relative}", :relative)

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="bg-white shadow sm:rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-base font-semibold leading-6 text-gray-900">Emails</h3>
          <div class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <%= for category <- @categories do %>
              <.link
                navigate={~p"/categories/#{category.id}"}
                class="relative flex items-center space-x-3 rounded-lg border border-gray-300 bg-white px-6 py-5 shadow-sm hover:border-gray-400"
              >
                <div class="min-w-0 flex-1">
                  <div class="focus:outline-none">
                    <span class="absolute inset-0" aria-hidden="true"></span>
                    <p class="text-sm font-medium text-gray-900">
                      {category.name}
                      <span class="ml-2 inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700">
                        {Map.get(@email_counts, category.id, 0)}
                      </span>
                    </p>
                    <p class="truncate text-sm text-gray-500">
                      {category.description}
                    </p>
                  </div>
                </div>
              </.link>
            <% end %>

            <.link
              navigate={~p"/categories/new"}
              class="relative flex items-center space-x-3 rounded-lg border-2 border-dashed border-gray-300 bg-white px-6 py-5 text-center hover:border-gray-400"
            >
              <div class="min-w-0 flex-1">
                <div class="focus:outline-none">
                  <span class="absolute inset-0" aria-hidden="true"></span>
                  <div class="flex justify-center">
                    <.icon name="hero-plus-circle" class="h-6 w-6 text-gray-400" />
                  </div>
                  <p class="mt-2 text-sm font-medium text-gray-900">Add Category</p>
                </div>
              </div>
            </.link>
          </div>
        </div>
      </div>

      <div class="bg-white shadow sm:rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-base font-semibold leading-6 text-gray-900">Email Sync Status</h3>
          <div class="mt-2 max-w-xl text-sm text-gray-500">
            <p>
              Last sync: {format_last_sync(@last_sync)}
              <%!-- <span phx-hook="TimeAgo" id="last-sync-time" data-timestamp={@last_sync}></span> --%>
            </p>
          </div>
          <div class="mt-5">
            <button
              type="button"
              phx-click="sync_now"
              class="inline-flex items-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500"
            >
              <.icon name="hero-arrow-path" class={["mr-2 h-4 w-4", @syncing? && "animate-spin"]} />
              {if @syncing?, do: "Syncing...", else: "Sync Now"}
            </button>
          </div>
        </div>
      </div>

      <div class="mt-16">
        <div class="sm:flex sm:items-center">
          <div class="sm:flex-auto">
            <h2 class="text-base font-semibold leading-6 text-gray-900">
              Connected Gmail Accounts
            </h2>
            <p class="mt-2 text-sm text-gray-700">
              Manage your connected Gmail accounts and their sync settings.
            </p>
          </div>
          <div class="mt-4 sm:ml-16 sm:mt-0 sm:flex-none">
            <button
              type="button"
              phx-click="connect_gmail"
              class="block rounded-md bg-indigo-600 px-3 py-2 text-center text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
            >
              Connect Gmail Account
            </button>
          </div>
        </div>

        <div :if={@gmail_accounts != []} class="mt-8 flow-root">
          <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
            <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
              <table class="min-w-full">
                <thead class="bg-white">
                  <tr>
                    <th
                      scope="col"
                      class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-3"
                    >
                      Email
                    </th>
                    <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                      Last Sync
                    </th>
                    <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                      Status
                    </th>
                    <th scope="col" class="relative py-3.5 pl-3 pr-4 sm:pr-3">
                      <span class="sr-only">Actions</span>
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white">
                  <%= for account <- @gmail_accounts do %>
                    <tr>
                      <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-3">
                        {account.email} {if account.is_primary, do: "(Primary)"}
                      </td>
                      <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                        {if account.last_sync_at,
                          do: Calendar.strftime(account.last_sync_at, "%Y-%m-%d %H:%M"),
                          else: "Never"}
                      </td>
                      <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                        {if account.sync_enabled, do: "Sync enabled", else: "Sync disabled"}
                      </td>
                      <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-3">
                        <button
                          type="button"
                          phx-click="toggle_sync"
                          phx-value-id={account.id}
                          class="text-indigo-600 hover:text-indigo-900"
                        >
                          {if account.sync_enabled, do: "Disable sync", else: "Enable sync"}
                        </button>
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
    """
  end
end
