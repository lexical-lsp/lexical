{"", 0} = System.cmd("epmd", ~w(-daemon))
random_number = :rand.uniform(500)

with :nonode@nohost <- Node.self() do
  {:ok, _pid} = :net_kernel.start([:"testing-#{random_number}@127.0.0.1"])
end

ExUnit.start(exclude: [:skip])

if Version.match?(System.version(), ">= 1.15.0") do
  Logger.configure(level: :none)
else
  Logger.remove_backend(:console)
end
