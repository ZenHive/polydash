defmodule Polydash.Repo do
  use Ecto.Repo,
    otp_app: :polydash,
    adapter: Ecto.Adapters.Postgres
end
