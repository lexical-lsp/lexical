# Lexical.Plugin

Extend lexical's functionality

## Overview
Plugins are used to extend lexical's functionality and provide opt-in diagnostics, completion, and code intelligence features without having to build inside of Lexical itself.

## Plugin Types
The goal of the plugin project is to have different types of plugins that affect lexical in different ways. Presently, only diagnostic plugins are supported. A diagnostic examines a mix project or a document and emits `Lexical.Plugin.V1.Diagnostic.Result` structs to direct the user's attention to any issues it finds.
Diagnostic plugins can be used to integrate code linters like `credo` or to enforce project-specific rules and coding practices.

### Creating a diagnostic plugin

Create a new mix project with `mix new my_plugin`, and edit the `mix.exs` file to include the `:lexical_plugin` app.

```elixir
def deps do
  [
     {:lexical_plugin, "~> 0.1.0"}
  ]
end
```

You will also need to add an application `env` key in your `mix.exs` to tell lexical that this is a plugin application. When an application is marked like this, its modules are searched for any that implement plugin behaviours. Add the application key like this:

```elixir
def application do
  [
        extra_applications: [:logger],
        env: [lexical_plugin: true]
  ]
```

Now we implement the plugin module. In our module, we're going to emit an error on the first line of every file we encounter with a message.

```elixir
defmodule NoisyPlugin do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic
  alias Lexical.Project

  use Diagnostic, name: :noisy_example_plugin

  def handle(%Document{} = doc) do
    results =
      if Document.size(doc) >= 1 do
        [build_result(doc.path)]
      else
        []
      end

    {:ok, results}
  end

  def handle(%Project{} = project) do
    root_path = Project.root_path(project)

    glob =
      if umbrella?(root_path) do
        "#{root_path}/apps/**/*.ex"
      else
        "#{root_path}/lib/**/*.ex"
      end

    results =
      glob
      |> Path.wildcard()
      |> Enum.map(&build_result/1)

    {:ok, results}
  end

  defp build_result(document_path) do
    Diagnostic.Result.new(
      document_path,
      1,
      "Do you want to start like this?",
      :information,
      "Noisy Plugin"
    )
  end

  defp umbrella?(root_path) do
    root_path
    |> Path.join("apps")
    |> File.dir?()
  end
end
```

...and that's it. Now, you can install that plugin in your project by adding it to the project's `mix.exs`, and when lexical starts, it will detect the plugin and every file in your project will have a little noisy error at the top.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `lexical_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lexical_plugin, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/lexical_plugin>.
