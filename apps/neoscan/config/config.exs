use Mix.Config

config :neoscan, ecto_repos: [Neoscan.Repo]

config :neoscan, use_block_cache: true

import_config "#{Mix.env()}.exs"
