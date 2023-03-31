import Config

if System.get_env("NAMESPACE") do
  # If the build directory has been namespaced earlier then it is
  # necessary to clean before running another build
  Mix.Task.run("clean")
  Mix.Shell.IO.info("$ mix clean")
end
