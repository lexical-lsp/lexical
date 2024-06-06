## Unreleased
* Organize Aliases by @scohen https://github.com/lexical-lsp/lexical/pull/725
* Remove unused aliases by @scohen
* Refactor: Pass env into completion in remote control by @scohen in https://github.com/lexical-lsp/lexical/pull/733
* Refactor: Increased type detail by @scohen in https://github.com/lexical-lsp/lexical/pull/734
* Fix: Edge case for module loading by @scohen in https://github.com/lexical-lsp/lexical/pull/738
* Improved store error handling by @scohen in https://github.com/lexical-lsp/lexical/pull/737
* Complete callables without parens if present in locals_without_parens by @zachallaun in https://github.com/lexical-lsp/lexical/pull/739
* Indexed delegated functions by @scohen in https://github.com/lexical-lsp/lexical/pull/729
* Fix: Crash when typing english by @scohen in https://github.com/lexical-lsp/lexical/pull/742
* Fix go to definition behavior for same-name, same-arity functions by directing to the first function by @scottming in https://github.com/lexical-lsp/lexical/pull/746
* Completion: show type spec for struct fields by @kirillrogovoy in https://github.com/lexical-lsp/lexical/pull/751
* Code Action: Add alias by @scohen in https://github.com/lexical-lsp/lexical/pull/740
* Fixed: Go to definitions crashes on modules defined via a macro by @scohen in https://github.com/lexical-lsp/lexical/pull/753
* Increased plugin timeouts by @scohen in https://github.com/lexical-lsp/lexical/pull/757
* Code Action: Remove unused aliases by @scohen in https://github.com/lexical-lsp/lexical/pull/748
* Reorder `test` macro completions by @zachallaun in https://github.com/lexical-lsp/lexical/pull/769
* Added struct definition detection for ecto schemas by @scohen in https://github.com/lexical-lsp/lexical/pull/758
* Sorted bang functions after non-bang variants by @scohen in https://github.com/lexical-lsp/lexical/pull/770

### v0.6.1

Small bugfix release. We found an issue regarding unicode conversion, and although it's existed for a while and no one complained, we felt that it was more likely to happen now that we have workspace symbols.

* Fix conversion of UTF-8 positions to UTF-16 code units by @zachallaun in https://github.com/lexical-lsp/lexical/pull/719
* Fix Entity.resolve not correctly resolving local function capture calls @scottming in https://github.com/lexical-lsp/lexical/pull/721

## v0.6.0 `24 April, 2024`
After multiple people asked, both document and workspace symbols have been implemented.
Both make heavy use of our indexing infrastructure, which provides extremely fast and
accurate results.

We've also fixed a number of small inconsistencies and crashes in the indexer, making it more robust and accurate. I especially want to call out the fix that @lukad made, that improved indexing performance by 3600x on his large codebase.
When you update to this release, we strongly recommend re-indexing your project's source code by opening the project's `mix.exs` file and
running the `Rebuild <your project>'s code search index` code action.

In addition, we've improved support for completions in phoenix controllers, stopped completions inside strings and have changed how we sort completions. The new sorting scheme is a big improvement for usability, and sorts things by how "close" they are to what you're working on. Give it a shot, we think you'll like it.

I'd like to thank all our new contributors, and especially our core team of
@scottming, @zachallaun, @moosieus and @blond. You've all gone above and beyond.

### What's Changed

* Add Sublime Text instructions to docs by @distefam in https://github.com/lexical-lsp/lexical/pull/633
* Implement callback completions by @Moosieus in https://github.com/lexical-lsp/lexical/pull/640
* Fix `do` completing to `defmodule` in VSCode by @Moosieus in https://github.com/lexical-lsp/lexical/pull/642
* Speed up indexing by not calling `deps_dir` for every file by @lukad in https://github.com/lexical-lsp/lexical/pull/646
* Fixed bug where blocks weren't popped correctly by @scohen in https://github.com/lexical-lsp/lexical/pull/647
* Fix crashing in unsaved vscode files by @Moosieus in https://github.com/lexical-lsp/lexical/pull/644
* Find references for variables by @scohen in https://github.com/lexical-lsp/lexical/pull/645
* New completion sorting approach by @Moosieus in https://github.com/lexical-lsp/lexical/pull/653
* Fixed issue where function definitions were returning references by @scohen in https://github.com/lexical-lsp/lexical/pull/655
* Document Symbols support by @scohen in https://github.com/lexical-lsp/lexical/pull/652
* Prevent spurious errors in .heex files by disabling the on-type compiler. by @Moosieus in https://github.com/lexical-lsp/lexical/pull/662
* Fixing crash when dealing with unicode files by @scohen in https://github.com/lexical-lsp/lexical/pull/672
* Fix: Non-string test names crash exunit indexer by @scohen in https://github.com/lexical-lsp/lexical/pull/676
* Added module attribute detection by @scohen in https://github.com/lexical-lsp/lexical/pull/679
* Impl suggest behaviours by @scohen in https://github.com/lexical-lsp/lexical/pull/681
* Support resolving Phoenix Controller modules. by @scottming in https://github.com/lexical-lsp/lexical/pull/659
* Completions: Handled nil origin and full name by @scohen in https://github.com/lexical-lsp/lexical/pull/689
* Fixed crash for in-progress module attributes by @scohen in https://github.com/lexical-lsp/lexical/pull/691
* For module definitions, use the `Indexer` version instead of `ElixirSense` by @scottming in https://github.com/lexical-lsp/lexical/pull/658
* Current modules can be nil by @scohen in https://github.com/lexical-lsp/lexical/pull/696
* Stopped completions inside strings by @scohen in https://github.com/lexical-lsp/lexical/pull/692
* Workspace symbols support by @scohen in https://github.com/lexical-lsp/lexical/pull/674
* Fix: Module suggestion was incorrect for files with multiple periods by @scohen in https://github.com/lexical-lsp/lexical/pull/705

**Full Changelog**: https://github.com/lexical-lsp/lexical/compare/v0.5.2...v0.6.0

## v0.5.2 `29 February, 2024`
This is a bugfix release that fixes the following:

* Updated credo by @scohen in #617
* Update nix hash with new deps by @hauleth in #618
* Prepare scripts for updating Nix hash by non-Nix users by @hauleth in #619
* Update the installation documentation for the supported Elixir version by @scottming in #624
* Fixed unused variable code action by @scohen in #628

## v0.5.1 `22 February, 2024`
This is a bugfix release that fixes an issue where lexical wouldn't start on MacOS if you're using the default bash, and not using one of the supported version managers (asdf, rtx or mise)

## v0.5.0 `21 February, 2024`
Admittedly, it's been a long while since the last release, but we've laid the groundwork for some exciting new features.

Since November, we've built out our search and indexing infrastructure that allows lexical to find interesting bits of your source code and highlight them for you later. We went through five separate backends before settling on one that is super duper fast, memory efficient(ish) and is written in pure elixir.

Presently, we're using this to power our newest features, find references and go to definition. We've implemented both for modules, module attributes and functions. You'll notice that when lexical starts, it will index your project's source code. This is a one-time operation that should be quick, indexing lexical's and its dependencies 193,000 lines of source code takes around 10 seconds. This means that indexing is on by default, and there's no way to turn it off any more. We've crossed the rubicon, folks, and there's no turning back.

Other good news, because of the indexing infrastructure, we no longer have to do a full build when lexical starts for the first time. This means the startup time has dramatically improved. On the lexical project, it has dropped from 12 seconds to 2.

I'd like to thank @scottming @zachallaun and @Blond11516 for ensuring that the current state of the code is where it is today. Also, thank you @hauleth for taking care of the nix flake.

And we've made a ton of bug fixes and usability improvements since 0.4.1 as well. Some highlights include:

* Support for elixir version 1.16
* Handled renaming of rtx to mise
* Multiple improvements to the hover popup
* Improved ease of writing new code actions
* Undefined variables diagnostics error for HEEx templates
* Code action: Suggested function names
* Completions for typespecs
* Improved nix flake

### What's Changed

* Correctly activate rtx during boot by @zachallaun in https://github.com/lexical-lsp/lexical/pull/430
* Improve incompatible version errors on boot by @zachallaun in https://github.com/lexical-lsp/lexical/pull/389
* i96: send and log messages by @jollyjerr in https://github.com/lexical-lsp/lexical/pull/420
* Put module below call signature for hover funs/types by @zachallaun in https://github.com/lexical-lsp/lexical/pull/434
* Fix diagnostics issue when `config_env` is called. by @scottming in https://github.com/lexical-lsp/lexical/pull/439
* Find References by @scohen in https://github.com/lexical-lsp/lexical/pull/405
* Code Actions refactor by @scohen in https://github.com/lexical-lsp/lexical/pull/453
* Consider arity in function ordering by @yerguden in https://github.com/lexical-lsp/lexical/pull/442
* Fix: Erlang function calls in pipes were incorrectly formatted by @scohen in https://github.com/lexical-lsp/lexical/pull/476
* Fix: Stutter when completing inside string interpolations by @scohen in https://github.com/lexical-lsp/lexical/pull/464
* Fix: Don't raise an exception if the build directory doesn't exist by @scohen in https://github.com/lexical-lsp/lexical/pull/481
* Add Vim ALE configuration details by @jparise in https://github.com/lexical-lsp/lexical/pull/484
* Removed unhelpful completion for :: symbol by @mdshamoon in https://github.com/lexical-lsp/lexical/pull/485
* Add heex to filetype list for neovim by @soundmonster in https://github.com/lexical-lsp/lexical/pull/487
* Added completions for typespecs by @scohen in https://github.com/lexical-lsp/lexical/pull/478
* Fix module completion error after a dot by @zachallaun in https://github.com/lexical-lsp/lexical/pull/496
* Add replacing unknown remote function to code actions by @sheldak in https://github.com/lexical-lsp/lexical/pull/443
* Move from flake-utils to flake-parts by @hauleth in https://github.com/lexical-lsp/lexical/pull/498
* Fix Diagnostic.Result to_lsp with 4-elem tuple position by @bangalcat in https://github.com/lexical-lsp/lexical/pull/502
* Optimise the manual loading of dependent apps and modules. by @scottming in https://github.com/lexical-lsp/lexical/pull/455
* Add instructions for LunarVim installation by @dimitarvp in https://github.com/lexical-lsp/lexical/pull/510
* Find function references by @scohen in https://github.com/lexical-lsp/lexical/pull/516
* Added percentage based progress reporters by @scohen in https://github.com/lexical-lsp/lexical/pull/519
* Added reindex command by @scohen in https://github.com/lexical-lsp/lexical/pull/522
* Support mise (new name for rtx) by @x-ji in https://github.com/lexical-lsp/lexical/pull/544
* Correctly applied code lens options by @scohen in https://github.com/lexical-lsp/lexical/pull/553
* Support Elixir 1.16 by @scottming in https://github.com/lexical-lsp/lexical/pull/535
* chore(nix): update deps hash by @hauleth in https://github.com/lexical-lsp/lexical/pull/557
* Resolve function definitions without parens by @zachallaun in https://github.com/lexical-lsp/lexical/pull/563
* Correctly resolve imported calls by @zachallaun in https://github.com/lexical-lsp/lexical/pull/565
* Implemented find references for module attributes by @scohen in https://github.com/lexical-lsp/lexical/pull/558
* Correctly resolve `&Module.function/arity` syntax by @zachallaun in https://github.com/lexical-lsp/lexical/pull/566
* Switched over to mise rather than rtx by @scohen in https://github.com/lexical-lsp/lexical/pull/580
* Struct discovery now uses the index by @scohen in https://github.com/lexical-lsp/lexical/pull/582
* Detected module references using __MODULE__ by @scohen in https://github.com/lexical-lsp/lexical/pull/603
* Bumped garbage collection for some of our more intensive processes by @scohen in https://github.com/lexical-lsp/lexical/pull/600
* Calling find references on a `defstruct` call finds defined structs by @scohen in https://github.com/lexical-lsp/lexical/pull/607
* Zipped package now keeps file permissions by @scohen in https://github.com/lexical-lsp/lexical/pull/609
* Excluded source files in build directory by @scohen in https://github.com/lexical-lsp/lexical/pull/610

## v0.4.1 `08 November, 2023`
This is a small bugfix release for 0.4.0

It contains the following fixes:

   * Fix: Stutter when completing some items inside strings (`:erl` would complete to `:erlerlang`)
   * Fix: Undefined variable names in HEEX templates
   * Fix: Erlang remote calls in pipelines did not have their first parameter removed during completion
   * Feature: Function names in completions are ordered by name and then arity

## v0.4.0 `24 October, 2023`
Welcome to Lexical v0.4.0

The main thrust of v0.4 is hover support and quality of life improvements. Now, when you hover over a module or function, you'll see relevant documentation, types and parameters. We've also spent a lot of time working on completions in #410, which makes them more consistent, fixes some bugs in certain language clients (like eglot adding an extra @ when completing module attributes), and greatly improves their feel in vscode.

Additionally, quite a few of the changes in this PR were about laying the groundwork for our indexing infrastructure, which will debut in the next version. But fear not, this version has indexing disabled.

I want to thank @zachallaun and @scottming for all their hard work on this release. They've made lexical faster, more friendly and have removed a bunch of bugs!

Highlights include:

   * Document hover for functions and modules
   * Improved boot scripts
   * Automatically updating nix flake. Thanks, @hauleth
   * Helix editor integration. Thanks @philipgiuliani
   * .heex integration
   * Massively improved completions (Check out the PR, it's too big to summarize)

Bugs fixed:

   * Longstanding unicode completion / editing bugs slain. Unicode works perfectly now.

### What's Changed

* Suggest a module name for defmodule completion by @scohen in https://github.com/lexical-lsp/lexical/pull/338
* Add Vanilla Emacs with eglot instruction by @dalugm in https://github.com/lexical-lsp/lexical/pull/343
* Add elixir boot script to support having spaces in the package path by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/345
* Centralize general-use AST modules in `common` by @zachallaun in https://github.com/lexical-lsp/lexical/pull/342
* Allow release workflow to update existing releases by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/346
* Fixed bug in path namespacing by @scohen in https://github.com/lexical-lsp/lexical/pull/350
* Convert utf8->latin1 before decoding JSON-RPC payloads by @zachallaun in https://github.com/lexical-lsp/lexical/pull/353
* Add support for `textDocument/hover` (for modules) by @zachallaun in https://github.com/lexical-lsp/lexical/pull/331
* Fix markdown formatting for supported versions by @reisub in https://github.com/lexical-lsp/lexical/pull/355
* Indexing features for modules by @scohen in https://github.com/lexical-lsp/lexical/pull/347
* Refactor: Moved Dispatch from server to remote_control by @scohen in https://github.com/lexical-lsp/lexical/pull/357
* Moved dispatch to :gen_event by @scohen in https://github.com/lexical-lsp/lexical/pull/358
* Integrated indexing into language server by @scohen in https://github.com/lexical-lsp/lexical/pull/359
* Fixed index store test failure by @scohen in https://github.com/lexical-lsp/lexical/pull/365
* Add `current_project/1` helper function by @scottming in https://github.com/lexical-lsp/lexical/pull/360
* Position refactor by @scohen in https://github.com/lexical-lsp/lexical/pull/364
* Added logos to project and readme by @scohen in https://github.com/lexical-lsp/lexical/pull/366
* Aliases was confused by nested non-module blocks by @scohen in https://github.com/lexical-lsp/lexical/pull/368
* Better typespecs by @scohen in https://github.com/lexical-lsp/lexical/pull/367
* Add Helix installation instructions by @philipgiuliani in https://github.com/lexical-lsp/lexical/pull/376
* Generate correct typespec for LSP messages by @zachallaun in https://github.com/lexical-lsp/lexical/pull/380
* Async indexing by @zachallaun in https://github.com/lexical-lsp/lexical/pull/371
* Enabled warnings-as-errors on umbrella by @scohen in https://github.com/lexical-lsp/lexical/pull/383
* Improved hover support: Structs, qualified calls and types, more info for modules by @zachallaun in https://github.com/lexical-lsp/lexical/pull/356
* Explicitly implement protocol in completion modules by @zachallaun in https://github.com/lexical-lsp/lexical/pull/386
* Refactor client capability tracking by @zachallaun in https://github.com/lexical-lsp/lexical/pull/385
* Support for HEEx compilation by @scottming in https://github.com/lexical-lsp/lexical/pull/323
* Made aliases better handle the __aliases__ special form by @scohen in https://github.com/lexical-lsp/lexical/pull/393
* Fix the `eex` compiled flaky test by @scottming in https://github.com/lexical-lsp/lexical/pull/394
* Enhanced ets / removed cub and mnesia backends. by @scohen in https://github.com/lexical-lsp/lexical/pull/392
* Disabled indexing by @scohen in https://github.com/lexical-lsp/lexical/pull/399
* Fix Field parsing error for zed editor by @scottming in https://github.com/lexical-lsp/lexical/pull/396
* Fix the struct `KeyError` diagnostics by @scottming in https://github.com/lexical-lsp/lexical/pull/397
* Always return `Completion.List` with `is_incomplete: true` by @zachallaun in https://github.com/lexical-lsp/lexical/pull/398
* Detect version manager the same way in all scripts by @zachallaun in https://github.com/lexical-lsp/lexical/pull/390
* Respond with `nil` instead of an error when formatting fails by @zachallaun in https://github.com/lexical-lsp/lexical/pull/411
* Fixup README word repeating by @solar05 in https://github.com/lexical-lsp/lexical/pull/414
* Made display name calculation relocatable by @scohen in https://github.com/lexical-lsp/lexical/pull/415
* Move `entity` module to `remote_control` app by @scottming in https://github.com/lexical-lsp/lexical/pull/406
* Reorder the startup order of the children of `Server.Project.Supervisor` by @scottming in https://github.com/lexical-lsp/lexical/pull/407
* Refactor completions to always use text edits by @zachallaun in https://github.com/lexical-lsp/lexical/pull/409
* Fix spec for `Lexical.Ast.cursor_path/2` by @zachallaun in https://github.com/lexical-lsp/lexical/pull/418
* Fix `path_at/2` to allow path to branches if they're innermost by @zachallaun in https://github.com/lexical-lsp/lexical/pull/419
* Improve completions by @zachallaun in https://github.com/lexical-lsp/lexical/pull/410
* Improved memory performance while indexing by @scohen in https://github.com/lexical-lsp/lexical/pull/421
* chore: update Nix definition by @hauleth in https://github.com/lexical-lsp/lexical/pull/417
* Make the operational behavior of the ancestors of structures and modules more consistent by @scottming in https://github.com/lexical-lsp/lexical/pull/408
* Refactor shell scripts and add Docker-based integration tests by @zachallaun in https://github.com/lexical-lsp/lexical/pull/395

**Full Changelog**: https://github.com/lexical-lsp/lexical/compare/v0.3.0...v0.4.0

### What's Changed

* Suggest a module name for defmodule completion by @scohen in https://github.com/lexical-lsp/lexical/pull/338
* Add Vanilla Emacs with eglot instruction by @dalugm in https://github.com/lexical-lsp/lexical/pull/343
* Add elixir boot script to support having spaces in the package path by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/345
* Centralize general-use AST modules in `common` by @zachallaun in https://github.com/lexical-lsp/lexical/pull/342
* Allow release workflow to update existing releases by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/346
* Fixed bug in path namespacing by @scohen in https://github.com/lexical-lsp/lexical/pull/350
* Convert utf8->latin1 before decoding JSON-RPC payloads by @zachallaun in https://github.com/lexical-lsp/lexical/pull/353
* Add support for `textDocument/hover` (for modules) by @zachallaun in https://github.com/lexical-lsp/lexical/pull/331
* Fix markdown formatting for supported versions by @reisub in https://github.com/lexical-lsp/lexical/pull/355
* Indexing features for modules by @scohen in https://github.com/lexical-lsp/lexical/pull/347
* Refactor: Moved Dispatch from server to remote_control by @scohen in https://github.com/lexical-lsp/lexical/pull/357
* Moved dispatch to :gen_event by @scohen in https://github.com/lexical-lsp/lexical/pull/358
* Integrated indexing into language server by @scohen in https://github.com/lexical-lsp/lexical/pull/359
* Fixed index store test failure by @scohen in https://github.com/lexical-lsp/lexical/pull/365
* Add `current_project/1` helper function by @scottming in https://github.com/lexical-lsp/lexical/pull/360
* Position refactor by @scohen in https://github.com/lexical-lsp/lexical/pull/364
* Added logos to project and readme by @scohen in https://github.com/lexical-lsp/lexical/pull/366
* Aliases was confused by nested non-module blocks by @scohen in https://github.com/lexical-lsp/lexical/pull/368
* Better typespecs by @scohen in https://github.com/lexical-lsp/lexical/pull/367
* Add Helix installation instructions by @philipgiuliani in https://github.com/lexical-lsp/lexical/pull/376
* Generate correct typespec for LSP messages by @zachallaun in https://github.com/lexical-lsp/lexical/pull/380
* Async indexing by @zachallaun in https://github.com/lexical-lsp/lexical/pull/371
* Enabled warnings-as-errors on umbrella by @scohen in https://github.com/lexical-lsp/lexical/pull/383
* Improved hover support: Structs, qualified calls and types, more info for modules by @zachallaun in https://github.com/lexical-lsp/lexical/pull/356
* Explicitly implement protocol in completion modules by @zachallaun in https://github.com/lexical-lsp/lexical/pull/386
* Refactor client capability tracking by @zachallaun in https://github.com/lexical-lsp/lexical/pull/385
* Support for HEEx compilation by @scottming in https://github.com/lexical-lsp/lexical/pull/323
* Made aliases better handle the __aliases__ special form by @scohen in https://github.com/lexical-lsp/lexical/pull/393
* Fix the `eex` compiled flaky test by @scottming in https://github.com/lexical-lsp/lexical/pull/394
* Enhanced ets / removed cub and mnesia backends. by @scohen in https://github.com/lexical-lsp/lexical/pull/392
* Disabled indexing by @scohen in https://github.com/lexical-lsp/lexical/pull/399
* Fix Field parsing error for zed editor by @scottming in https://github.com/lexical-lsp/lexical/pull/396
* Fix the struct `KeyError` diagnostics by @scottming in https://github.com/lexical-lsp/lexical/pull/397
* Always return `Completion.List` with `is_incomplete: true` by @zachallaun in https://github.com/lexical-lsp/lexical/pull/398
* Detect version manager the same way in all scripts by @zachallaun in https://github.com/lexical-lsp/lexical/pull/390
* Respond with `nil` instead of an error when formatting fails by @zachallaun in https://github.com/lexical-lsp/lexical/pull/411
* Fixup README word repeating by @solar05 in https://github.com/lexical-lsp/lexical/pull/414
* Made display name calculation relocatable by @scohen in https://github.com/lexical-lsp/lexical/pull/415
* Move `entity` module to `remote_control` app by @scottming in https://github.com/lexical-lsp/lexical/pull/406
* Reorder the startup order of the children of `Server.Project.Supervisor` by @scottming in https://github.com/lexical-lsp/lexical/pull/407
* Refactor completions to always use text edits by @zachallaun in https://github.com/lexical-lsp/lexical/pull/409
* Fix spec for `Lexical.Ast.cursor_path/2` by @zachallaun in https://github.com/lexical-lsp/lexical/pull/418
* Fix `path_at/2` to allow path to branches if they're innermost by @zachallaun in https://github.com/lexical-lsp/lexical/pull/419
* Improve completions by @zachallaun in https://github.com/lexical-lsp/lexical/pull/410
* Improved memory performance while indexing by @scohen in https://github.com/lexical-lsp/lexical/pull/421
* chore: update Nix definition by @hauleth in https://github.com/lexical-lsp/lexical/pull/417
* Make the operational behavior of the ancestors of structures and modules more consistent by @scottming in https://github.com/lexical-lsp/lexical/pull/408
* Refactor shell scripts and add Docker-based integration tests by @zachallaun in https://github.com/lexical-lsp/lexical/pull/395


**Full Changelog**: https://github.com/lexical-lsp/lexical/compare/v0.3.3...v0.4.0

## v0.3.3 `05 September, 2023`
Fixed Unicode handling.

Unicode was likely broken under the last several releases; Unicode in documents would result in incorrect errors popping up. This has been fixed, and was due to incorrect decoding in the standard input handler.

**Full Changelog**: https://github.com/lexical-lsp/lexical/compare/v0.3.2...v0.3.3

## v0.3.2 `29 August, 2023`
0.3.2 fixes a bug where packaging would not produce namespaced artifacts if the lexical directory was inside a subdirectory that had one of its dependencies as a path element.

For example, packaging would fail if lexical was in `/path/to/home/language_servers/lexical`.

**Full Changelog**: https://github.com/lexical-lsp/lexical/compare/v0.3.1...v0.3.2

## v0.3.1 `24 August, 2023`

This is a bugfix release. Packaging generated in v0.3.0 would not start in directories that contain spaces, and this is the default for vscode under macOS.
This release has a new launching mechanism that should allow us to use a lot less bash scripting.

## v0.3.0 `23 August, 2023`

### What's Changed

* Support Struct fields completion when in struct arguments context by @scottming in https://github.com/lexical-lsp/lexical/pull/196
* Fix: Argument names crashes in light of a literal atom by @scohen in https://github.com/lexical-lsp/lexical/pull/285
* Add Nix Flake by @hauleth in https://github.com/lexical-lsp/lexical/pull/175
* ci: Require strict versions from erlef/setup-beam by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/289
* Refactor: Extracted Build.Project by @scohen in https://github.com/lexical-lsp/lexical/pull/292
* Fixed code unit / codepoint confusion by @scohen in https://github.com/lexical-lsp/lexical/pull/290
* Fixed project node naming conflicts by @scohen in https://github.com/lexical-lsp/lexical/pull/294
* Remove logger for debugging port stdin/sdtout by @scottming in https://github.com/lexical-lsp/lexical/pull/298
* Added support for per-file .eex compilation by @scohen in https://github.com/lexical-lsp/lexical/pull/296
* Added default case by @scohen in https://github.com/lexical-lsp/lexical/pull/305
* Config compiler by @scohen in https://github.com/lexical-lsp/lexical/pull/304
* Namespacing refinements by @scohen in https://github.com/lexical-lsp/lexical/pull/307
* Update architecture.md with spelling corrections by @axelclark in https://github.com/lexical-lsp/lexical/pull/310
* Improve the documentation related to `neovim` installation. by @scottming in https://github.com/lexical-lsp/lexical/pull/308
* Handle presense of multiple version managers by @awerment in https://github.com/lexical-lsp/lexical/pull/311
* make sure not to choke on non-export prefixed path lines by @andyleclair in https://github.com/lexical-lsp/lexical/pull/312
* Second attempt to make struct completion more consistent by @scottming in https://github.com/lexical-lsp/lexical/pull/225
* Added installation instructions for Vim + Vim-LSP by @jHwls in https://github.com/lexical-lsp/lexical/pull/315
* Reworked lexical packaging by @scohen in https://github.com/lexical-lsp/lexical/pull/314
* Development docs by @scohen in https://github.com/lexical-lsp/lexical/pull/316
* Fix extraneous logging in test by @scohen in https://github.com/lexical-lsp/lexical/pull/317
* Update paths to start_lexical.sh in installation.md by @edwardsmit in https://github.com/lexical-lsp/lexical/pull/318
* Fix: Flaky tests by @scohen in https://github.com/lexical-lsp/lexical/pull/320
* Support for erlang 26 by @scohen in https://github.com/lexical-lsp/lexical/pull/319
* Fix typo of package task by @scottming in https://github.com/lexical-lsp/lexical/pull/321
* Fix VSCode installation instructions by @miXwui in https://github.com/lexical-lsp/lexical/pull/325
* Fix package task generating empty ZIPs by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/334
* Removed plugin_runner app by @scohen in https://github.com/lexical-lsp/lexical/pull/327
* Added development docs suggestions by @scohen in https://github.com/lexical-lsp/lexical/pull/333
* Added discord link and build badges by @scohen in https://github.com/lexical-lsp/lexical/pull/335
* 0.3.0 Release by @scohen in https://github.com/lexical-lsp/lexical/pull/337
* Context-aware "use" completions by @scohen in https://github.com/lexical-lsp/lexical/pull/336

**Full Changelog**: https://github.com/lexical-lsp/lexical/compare/v0.2.2...v0.3.0

## v0.2.2 `21 July, 2023`

### What's Changed

* fix: Add missing command to get rtx env by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/281
* Update Lexical version to 0.2.2 by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/282


**Full Changelog**: https://github.com/lexical-lsp/lexical/compare/v0.2.1...v0.2.2

## v0.2.1 `21 July, 2023`
This release bumps versions of our apps, and contains no improvements or fixes.

## v0.2.0 `21 July, 2023`

### What's Changed

* Handled Cancel Notifications by @scohen in https://github.com/lexical-lsp/lexical/pull/157
* Support work done progress during project compilation by @scottming in https://github.com/lexical-lsp/lexical/pull/135
* Normalize naming by @scohen in https://github.com/lexical-lsp/lexical/pull/158
* Addressed deadlocks in Document Store by @scohen in https://github.com/lexical-lsp/lexical/pull/160
* Fix diagnostic for missing fields due to @enforce_keys by @scottming in https://github.com/lexical-lsp/lexical/pull/162
* Enable --warnings-as-errors in CI by @scottming in https://github.com/lexical-lsp/lexical/pull/154
* Added file watching by @scohen in https://github.com/lexical-lsp/lexical/pull/164
* Fix CreateWorkDoneProgress for VScode and Emacs by @scottming in https://github.com/lexical-lsp/lexical/pull/161
* Fixed infinite loop in document updates by @scohen in https://github.com/lexical-lsp/lexical/pull/166
* Alias only returns modules by @scohen in https://github.com/lexical-lsp/lexical/pull/168
* Added fragment capabilities to document by @scohen in https://github.com/lexical-lsp/lexical/pull/170
* Fix record missing key's error by @scottming in https://github.com/lexical-lsp/lexical/pull/174
* Do not create intermediate binaries by @hauleth in https://github.com/lexical-lsp/lexical/pull/176
* Improved README.md by @scohen in https://github.com/lexical-lsp/lexical/pull/177
* Removed string-based completion env operations by @scohen in https://github.com/lexical-lsp/lexical/pull/172
* Fixed code actions / improved code mod api by @scohen in https://github.com/lexical-lsp/lexical/pull/179
* Remove patch from progress/state_test by @scottming in https://github.com/lexical-lsp/lexical/pull/180
* Improved struct completion by @scohen in https://github.com/lexical-lsp/lexical/pull/181
* fix(asdf): change order of installation by @03juan in https://github.com/lexical-lsp/lexical/pull/186
* Improve completions with default arguments by @scohen in https://github.com/lexical-lsp/lexical/pull/187
* New project structure / beginning of plugins by @scohen in https://github.com/lexical-lsp/lexical/pull/184
* Pulled out the name of arguments in pattern match args by @scohen in https://github.com/lexical-lsp/lexical/pull/193
* Removed initial compile by @scohen in https://github.com/lexical-lsp/lexical/pull/194
* Fix the parameter issue of Remote Callable in pipeline. by @scottming in https://github.com/lexical-lsp/lexical/pull/188
* Removed wx and et applications by @scohen in https://github.com/lexical-lsp/lexical/pull/201
* Improve UX when completing struct by @scottming in https://github.com/lexical-lsp/lexical/pull/190
* Added a check for credo pipeline initial argument by @scohen in https://github.com/lexical-lsp/lexical/pull/200
* We now use Lexical.Plugin.Diagnostics by @scohen in https://github.com/lexical-lsp/lexical/pull/197
* Fix the NAMESPACE=1 release issue by @scottming in https://github.com/lexical-lsp/lexical/pull/203
* Boost callable completions that are not double underscore/default by @viniciusmuller in https://github.com/lexical-lsp/lexical/pull/195
* Reduces behaviour_info/1 priority in completions by @viniciusmuller in https://github.com/lexical-lsp/lexical/pull/205
* Suggest behavior callbacks by @doughsay in https://github.com/lexical-lsp/lexical/pull/206
* fix: completion context can be null by @hauleth in https://github.com/lexical-lsp/lexical/pull/210
* Module sorting / Refactor boost by @scohen in https://github.com/lexical-lsp/lexical/pull/212
* Dependency structs were not being detected by @scohen in https://github.com/lexical-lsp/lexical/pull/213
* Load project config before compiling by @scohen in https://github.com/lexical-lsp/lexical/pull/215
* Plugin Architecture by @scohen in https://github.com/lexical-lsp/lexical/pull/211
* Refactor: Completion.Results are now Completion.Candidates by @scohen in https://github.com/lexical-lsp/lexical/pull/216
* ci: Tag release workflow by @Blond11516 in https://github.com/lexical-lsp/lexical/pull/221
* Added versions to plugins by @scohen in https://github.com/lexical-lsp/lexical/pull/219
* Bring the 1.15 version `Code` and `:elixir_tokenizer` into lexical  by @scottming in https://github.com/lexical-lsp/lexical/pull/217
* Support map fields completion by @scottming in https://github.com/lexical-lsp/lexical/pull/226
* Plugin packaging by @scohen in https://github.com/lexical-lsp/lexical/pull/222
* Support projects having the same directory name as a dependency by @scohen in https://github.com/lexical-lsp/lexical/pull/227
* Docs: Installation by @scohen in https://github.com/lexical-lsp/lexical/pull/229
* Fixed plugins for external projects by @scohen in https://github.com/lexical-lsp/lexical/pull/230
* Add neovim minimal configuaration by @scottming in https://github.com/lexical-lsp/lexical/pull/240
* Fixed failing builds by @scohen in https://github.com/lexical-lsp/lexical/pull/241
* Fix the issue of project name being too long by @scottming in https://github.com/lexical-lsp/lexical/pull/239
* Updated to work with older versions of elixir / erlang by @scohen in https://github.com/lexical-lsp/lexical/pull/235
* [issue-178] Snippet translations for  macro by @Sleepful in https://github.com/lexical-lsp/lexical/pull/208
* [issue-178] Fix macro_test by @Sleepful in https://github.com/lexical-lsp/lexical/pull/246
* Compile warnings by @scohen in https://github.com/lexical-lsp/lexical/pull/250
* WIP: Alias module by @scohen in https://github.com/lexical-lsp/lexical/pull/236
* Fixed boundary issue by @scohen in https://github.com/lexical-lsp/lexical/pull/249
* GitHub Actions improvements by @scohen in https://github.com/lexical-lsp/lexical/pull/245
* Fixing flaky tests by @scohen in https://github.com/lexical-lsp/lexical/pull/252
* Aliases can fail by @scohen in https://github.com/lexical-lsp/lexical/pull/251
* Generate `.gitignore` for `.lexical` project workspace by @zachallaun in https://github.com/lexical-lsp/lexical/pull/218
* Rebuild PLT files on projects dep changes by @scohen in https://github.com/lexical-lsp/lexical/pull/253
* Changed docs to indicate support for 1.13 and erl 24 by @scohen in https://github.com/lexical-lsp/lexical/pull/257
* Enforced project name validity by @scohen in https://github.com/lexical-lsp/lexical/pull/258
* Removed double compilation by @scohen in https://github.com/lexical-lsp/lexical/pull/259
* Completion improvements by @scohen in https://github.com/lexical-lsp/lexical/pull/260
* The start line can be the end line by @scohen in https://github.com/lexical-lsp/lexical/pull/264
* Fixed protocol consolidation by @scohen in https://github.com/lexical-lsp/lexical/pull/265
* Heavy refactor of namespacing by @scohen in https://github.com/lexical-lsp/lexical/pull/266
* Namespacing fixes / simplifications by @scohen in https://github.com/lexical-lsp/lexical/pull/268
* Quieted compile warnings in test by @scohen in https://github.com/lexical-lsp/lexical/pull/270
* Support Elixir 1.15 by @scottming in https://github.com/lexical-lsp/lexical/pull/261
* Re-enabled multiple version support by @scohen in https://github.com/lexical-lsp/lexical/pull/269
* Loadconfig needs to be called before deps are compiled by @scohen in https://github.com/lexical-lsp/lexical/pull/275
* Added default candidate case by @scohen in https://github.com/lexical-lsp/lexical/pull/274
* Replace with underscore can fail by @scohen in https://github.com/lexical-lsp/lexical/pull/276
* Preparing for 0.2.0 release by @scohen in https://github.com/lexical-lsp/lexical/pull/278

**Full Changelog**: https://github.com/lexical-lsp/lexical/compare/4367692...v0.2.0
