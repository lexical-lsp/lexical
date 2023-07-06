# Installation

The following instructions document how to install Lexical after
building from source. Some editors, like Visual Studio Code, have the
ability to automatically install the latest version of Lexical for
you.

## Caveats

 * Presently, Lexical works on Elixir 1.13 and 1.14 under Erlang
 24 and 25. We are actively working on supporting Elixir 1.15, and then
 erlang 26.

 * While it's within Lexical's capabilities to run your project in a
 different elixir and erlang version than Lexical is built with,
 presently, we don't support running your project in a different
 elixir and or erlang version.  We aim to fix this very shortly, as
 this dramatically limits Lexical's usefulness when working with
 multiple projects.


## Prerequisites

The first step in getting Lexical running locally is to clone the git
repository. Do this with

```elixir
git clone git@github.com:lexical-lsp/lexical.git
```

Then change to the lexical directory
```shell
cd lexical
```
...and build the project

```shell
make release.namespaced
```

If things complete successfully, you will then have a release in your
`build/dev/rel/lexical` directory. If you see errors, please file a
bug.

For the following examples, assume the absolute path to your Lexical
source code is `/my/home/projects/lexical`.

## Editor-specific setup
1. [Vanilla Emacs with lsp-mode](#vanilla-emacs-with-lsp-mode)
2. [Vanilla Emacs with eglot](#vanilla-emacs-with-eglot)
3. [Visual Studio Code](#visual-studio-code)
4. [neovim](#neovim)

## Vanilla Emacs with lsp-mode
The emacs instructions assume you're using `use-package`, which you
really should be. In your `.emacs.d/init.el` (or wherever you put your
emacs configuration), insert the following code:

```lisp
(use-package lsp-mode
  :ensure t
  :config
  (setq lsp-modeline-code-actions-segments '(count icon name))

  :init
  '(lsp-mode))


(use-package elixir-mode
  :ensure t
  :custom
  (lsp-elixir-server-command '("/my/home/projects/_build/dev/rel/lexical/start_lexical.sh")))

```

Restart emacs, and Lexical should start when you open a file with a
`.ex` extension.


## Vanilla Emacs with eglot

Eglot has a couple of utf8 related bugs that make it fail with
Lexical, and is not supported at this time.


## Visual Studio Code

Click on the extensions button on the sidebar, then search for
`lexical`, then click `install`.  By default, the extension will automatically
download the latest version of Lexical.

To change to a local executable, go to `Settings -> Extensions -> Lexical` and
type `/my/home/projects/lexical/_build/dev/rel/lexical` into the text box in
the `Server: Release path override` section.

## neovim

The key is to append the custom LS configuration to [lspconfig](https://github.com/neovim/nvim-lspconfig), so regardless of whether you are using mason or others, you can use this minimal configuration below as a reference:

```lua
    local lspconfig = require("lspconfig")
    local configs = require("lspconfig.configs")

    local lexical_config = {
      filetypes = { "elixir", "eelixir", },
      cmd = { "/my/home/projects/_build/dev/rel/lexical/start_lexical.sh" },
      settings = {},
    }

    if not configs.lexical then
      configs.lexical = {
        default_config = {
          filetypes = lexical_config.filetypes,
          cmd = lexical_config.cmd,
          root_dir = function(fname)
            return lspconfig.util.root_pattern("mix.exs", ".git")(fname) or vim.loop.os_homedir()
          end,
          -- optional settings
          settings = lexical_config.settings,
        },
      }
    end

    lspconfig.lexical.setup({})
```
