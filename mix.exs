defmodule GenPrerender.MixProject do
  use Mix.Project

  @version "0.0.14-beta.2"

  @description "caching made fun!"

  def project do
    [
      app: :gen_spoxy,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: @description,
      name: "GenSpoxy",
      docs: [
        extras: ["README.md"],
        source_url: "https://github.com/spotim/gen_spoxy"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:uuid, "~> 1.1"},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:credo, "~> 0.3", only: [:dev, :test]}
    ]
  end

  defp package() do
    [
      licenses: ["MIT License"],
      maintainers: ["Yaron Wittenstein"],
      links: %{"Github" => "https://github.com/spotim/gen_spoxy"},
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", ".formatter.exs"]
    ]
  end
end
