Code.load_file("test/gen_prerender_macros.exs")

ExUnit.configure(max_cases: 1)
ExUnit.start(exclude: [:skip])
