# Lexical

Lexical is a next-generation language server for the Elixir programming language.

## Features

  * Context aware code completion
  * As-you-type compilation
  * Advanced error highlighting
  * Code actions
  * Code Formatting
  * Go To Definition
  * Completely isolated build environment

## What makes Lexical different?
There are a couple things that lexical does differently than other language servers. Let's look at what separates it from
the pack.

#### Architecture

When lexical starts, it boots an erlang virtual machine that runs the language server and its code. It then boots a
separate virtual machine that runs your project code and connects the two via distribution. This provides the following benefits:

  * None of lexical's dependencies will conflict with your project. This means that lexical can make use of dependencies to make developing in it easier without having to "vendor" them. It also means that you can use lexical to work on your project, **even if lexical depends on your project**.
  * Your project can depend on a different version of elixir and erlang than lexical itself. This means that lexical can make use of the latest versions of elixir and erlang while still supporting projects that run on older versions.
  * The build environment for your project is only aware of your project, which enables as-you-type compilation and error reporting.
  * In the future, there is a possibility of having the lexical vm instance control multiple projects

#### Ease of contribution

Lexical has been designed to be easy to contribute to and work on. It features:

  * A consistent data model that represents the Language Server Protocol and `mix` tasks to generate new Language Server models.
  * A clearly defined separation between the language server and project code
  * A set of utilities that deal with manipulating code
  * A set of unit tests and test cases that make testing new features easy.

#### Focus on developer productivity

Lexical is also built with an eye on increasing developer productivity, and approaches some common features a little bit
differently. For example, Lexical's code completion is _context aware_, which means that if you type `alias MyModule.|`
you will only receive completions for modules and not the names of functions in `MyModule`. This awareness will extend
to other areas, which means:

  * You won't see completions for random functions and types in strings. In fact, when extended to string literals, Lexical will only show you completions if you're inside of an interpolation (`"hello there #{na|}'`).
  * If you're inside of a struct reference (`%StructModule.|`), you will only see modules listed that define structs, or are the parents of modules that define structs.

Because of this focus, Lexical aims to deliver depth of features rather than breadth of them. We'll likely spend
more time making sure each thing we add works and feels _just right_ rather than adding a whole slew of features
that people mostly won't use.

#### As you type compilation
Because your project is run in a separate virtual machine, we can compile the code that you're working on as you
type. This means you see errors _immediately_ rather than having to wait for a save. The result is you see and
fix typos, warnings, unused variables and a whole host of errors when they occur, which makes your code better,
faster.

## Installation

Follow the [Detailed Installation Instructions](pages/installation.md)

 ```
 mix package
 ```

 Lexical will now be available in `_build/dev/package/lexical`

If you would like to change the output directory, you can do so with the `--path` option

```
mix package --path /path/to/lexical
```

Lexical will be available in `/path/to/lexical`.

## Development

You're going to need a local instance in order to develop lexical, so follow the [Detailed Installation Instructions](pages/installation.md) first.

Then, install the git hooks with

```
mix hooks
```

These are pre-commit hooks that will check for correct formatting and run credo for you.

After this, you're ready to put together a pull request for Lexical!


### Debugging

Lexical supports a debug shell, which will connect a remote shell to a
currently-running language server process. To use it, `cd` into your
lexical installation directory and run

```
./bin/debug_shell.sh <name of project>
```

For example, if I would like to run the debug server for a server
running in your `lexical` project, run:

```
./bin/debug_shell.sh lexical
```

...and you will be connected to a remote IEx session _inside_ my
language server. This allows you to investigate processes, make
changes to the running code, or run `:observer`.

While in the debugging shell, all the functions in
`Lexical.Server.IEx.Helpers` are imported for you, and some common
modules, like like `Lexical.Project` and `Lexical.Document` are
aliased.

You can also start the lexical server in interactive mode via
`./bin/start_lexical.sh iex`. Combining this with the helpers that are
imported will allow you to run projects and do completions entirely in
the shell.

  *Note*: The helpers assume that all of your projects are in folders that are siblings with your lexical project.

Consider the example shell session:

```
./bin/start_lexical.sh iex
iex(1)> start_project :other
# the project in the ../other directory is started
compile_project(:other)
# the other project is compiled
iex(2)> complete :other, "defmo|"
[
  #Protocol.Types.Completion.Item<[
    detail: "",
    insert_text: "defmacro ${1:name}($2) do\n  $0\nend\n",
    insert_text_format: :snippet,
    kind: :class,
    label: "defmacro (Define a macro)",
    sort_text: "093_defmacro (Define a macro)"
  ]>,
  #Protocol.Types.Completion.Item<[
    detail: "",
    insert_text: "defmacrop ${1:name}($2) do\n  $0\nend\n",
    insert_text_format: :snippet,
    kind: :class,
    label: "defmacrop (Define a private macro)",
    sort_text: "094_defmacrop (Define a private macro)"
  ]>,
  #Protocol.Types.Completion.Item<[
    detail: "",
    insert_text: "defmodule ${1:module name} do\n  $0\nend\n",
    insert_text_format: :snippet,
    kind: :class,
    label: "defmodule (Define a module)",
    sort_text: "092_defmodule (Define a module)"
  ]>
]
```

The same kind of support is available when you run `iex -S mix` in the
lexical directory, and is helpful for narrowing down issues without
disturbing your editor flow.
