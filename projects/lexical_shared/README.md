# Lexical Core data structures and modules

This package contains some of the core data structures used in the Lexical Language
server, and for building Lexical Plugins.

## Installation
If you're building a plugin, this package should be included when you add `lexical_plugin` to your deps.

If, for some reason, you want to include it manually, do the following:

```elixir
def deps do
  [
    {:lexical_shared, "~> 0.1.0", optional: true}
  ]
end
```

Complete documenation here: <https://hexdocs.pm/lexical_shared>.
