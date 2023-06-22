# Lexical Credo - A Lexical plugin that enables credo checks

This is a plugin to lexical (our first) that enables [Credo](https://github.com/rrrene/credo) to
run whenever you type. Now you can immediately see and address any issues that credo flags when you
make them.

It's essential to have this as a test dependency, as lexical runs your code in test mode by default.

## Installation

```elixir
def deps do
  [
    {:lexical_credo, "~> 0.1.0", only: [:dev, :test]}
  ]
end
```

When starting lexical, you should see the following in your `project.log` file in the project's `.lexical`
directory:

```
info: Loaded [:lexical_credo]
```

Once you see that, you should start seeing Credo diagnostics in your editor.


## Notes on the plugin

The plugin runs Credo whenever you type, and most of your settings will be respected... for the most part.
Because Credo is designed to work with files on the disk, and the code you're editing isn't the same as
the code that's on the disk, we are sending the file's contents to Credo via standard output. However, when
we do this, Credo doesn't have a provision to provide the file name and the filename is lost.
This means that there's no way for Credo to know if the file is being ignored by your project, and you'll see
errors in it as you type. However, the errors will disappear once you save the file.
