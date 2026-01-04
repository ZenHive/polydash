defmodule Polydash.Repo do
  @moduledoc """
  Ecto repository for Polydash database operations.
  """
  use Ecto.Repo,
    otp_app: :polydash,
    adapter: Ecto.Adapters.Postgres
end
