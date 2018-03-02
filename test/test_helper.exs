Code.load_file("test/test_macros.exs")

ExUnit.configure(max_cases: 1)
ExUnit.start(exclude: [:skip])
