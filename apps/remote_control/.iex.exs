alias Lexical.Project
alias Lexical.RemoteControl

other_project =
  [
    File.cwd!(),
    "..",
    "..",
    "..",
    "eakins"
  ]
  |> Path.join()
  |> Path.expand()

project = Lexical.Project.new("file://#{other_project}")

RemoteControl.start_link(project, self())
