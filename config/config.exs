use Mix.Config

config_file = Path.expand(".", "config/#{Mix.env()}.exs")

if File.exists?(config_file) do
  import_config(config_file)
end
