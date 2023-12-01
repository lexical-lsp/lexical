{"", 0} = System.cmd("epmd", ~w(-daemon))
random_number = :rand.uniform(500)

with :nonode@nohost <- Node.self() do
  {:ok, _pid} = :net_kernel.start([:"testing-#{random_number}@127.0.0.1"])
end

Application.ensure_all_started(:common)
ExUnit.start(exclude: [:skip])
