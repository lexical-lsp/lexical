# Installation

The following instructions document how to install Lexical after
building from source. Some editors, like Visual Studio Code, have the
ability to automatically install the latest version of Lexical for
you.

## Caveats

Lexical supports the following versions of Elixir and Erlang:

| Erlang      | Version range    | Notes  |
| ----------- |----------------- | ------ |
|  24         | `>= 24.3.4.12`   | Might run on older versions; this was the lowest that would compile on arm |
|  25         | `>= 25.0`        |        |
|  26         | In progress      |        |

| Elixir   | Version Range  | Notes    |
| -------- | -------------- | -------- |
| 1.13     |    `>= 1.13.4` |          |
| 1.14     |    `all`       |          |
| 1.15     | `>= 1.15.3`    | `1.15.0` - `1.15.2` had compiler bugs that prevented lexical from working |

Lexical can run projects in any version of Elixir and Erlang that it supports, but it's important to understand that Lexical needs to be compiled under the lowest version of elixir and erlang that you intend to use it with. That means if you have the following projects:
 
   * `first`: elixir `1.14.4` erlang `24.3.2`
   * `second`: elixir `1.14.3` erlang `25.0`
   * `third`: elixir: `1.13.3` erlang `25.2.3`

Lexical would need to be compiled with Erlang `24.3.2` and Elixir `1.13.3`. 
Lexical's prepackaged builds use Erlang `24.3.4.12` and Elixir `1.13.4`

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
NAMESPACE=1 mix release lexical --overwrite
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

Lexical doesn't work in neovim `< 0.9.0`.

In version `>= 0.9.0`, the key is to append the custom LS configuration to [lspconfig](https://github.com/neovim/nvim-lspconfig), so regardless of whether you are using mason or others, you can use this configuration below as a reference:

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

If the configuration above doesn't work for you, please try this minimal [neovim configuration](https://github.com/scottming/nvim-mini-for-lexical), It can eliminate other plugin factors.
