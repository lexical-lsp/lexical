defmodule Mix.Dialyzer do
  def dependency do
    {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false}
  end

  def config do
    [
      plt_core_path: absolute_path("priv/plts"),
      plt_file: {:no_warn, absolute_path("priv/plts/dialyzer.plt")},
      plt_add_deps: :apps_direct,
      plt_add_apps: [:wx, :mix, :ex_unit, :compiler],
      ignore_warnings: absolute_path("dialyzer.ignore-warnings")
    ]
  end

  def absolute_path(relative_path) do
    __ENV__.file
    |> Path.dirname()
    |> Path.join(relative_path)
  end
end
