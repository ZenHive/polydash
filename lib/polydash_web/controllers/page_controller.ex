defmodule PolydashWeb.PageController do
  use PolydashWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
