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
