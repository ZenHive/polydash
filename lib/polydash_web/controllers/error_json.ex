defmodule PolydashWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  @doc """
  Renders a JSON error response based on the template name.

  Returns a map with the HTTP status message corresponding to the template.
  For example, "404.json" becomes `%{errors: %{detail: "Not Found"}}`.
  """
  @spec render(String.t(), map()) :: %{errors: %{detail: String.t()}}
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
