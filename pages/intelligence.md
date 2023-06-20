# Code intelligence

We'd like to replace elixir_sense with our own implementation for the following bits
of code intelligence.

 * Go to definition
 * Find references
 * Refactoring

In order to have this level of intelligence of elixir code, we need to
search both beam files and source code to discover relevant parts and
locations of elixir and erlang code, index them an make them
searchable. This is a large task that will not be accomplished in one
commit, and this document will help to lay out the scope of the work,
as well as collect thoughts and drive the implementation.

Code intelligence will be oragnized into the following discrete areas:

* **Discovery** - Finding points of interest in the project's codebase, dependencies and elixir core modules
* **Caching** - Writing the discovered items to disk and ensuring the index is up to date with the state of the project at *all times*. The goal here is to never have to delete the `.lexical` directory.
* **Indexing** - Storing the discovered artifacts in a local in-memory index that enable fast searching.
* **Searching** ideally using something like the [sublime text's fuzzy search](https://www.forrestthewoods.com/blog/reverse_engineering_sublime_texts_fuzzy_match/), but we definitely need some type of fuzzy search.
* **Recognition** For several of the above examples (go to definition, find references), we need to be able to recognize what our cursor is hovering over. Is it a module? An atom? a variable? etc.

# Discovery
Lexical needs a flexible, expandable discovery engine. It needs to be
able to examine both artifacts on disk like beam files and source
code, and to index code that's being edited by the user. Right from
the start, it needs to be able to find the following items:

 * Modules
 * Public and private module functions
 * Macros
 * Anonymous functions
 * Structs
 * Records
 * Types
 * Variables
 * Atoms?
 * Additional items, defined in plugins

While investigating the above items, we will need to take into account
the difference between usages and definitions. This will be pretty
clear for most items (though aliasing and importing might muddy the
waters somewhat), but atoms will be difficult, since there's no
defintion to speak of, just a usage.

# Caching
> There are only two hard problems in computer science: Naming things, cache invalidation and off by one errors.

Indexing the entire project, its dependencies, elixir and erlang when
the language server starts is likely going to be too performance
intensive to do (to wit, rewriting atoms during namespacing takes 15
seconds on our moderately sized project), so we will need some sort of
on-disk representation of the index.

Such a representation will need to take the following into account:

  * Branches can while the language server is running, invalidating large portions of the cache
  * Project level search and replace can affect large numbers of files at once
  * The versions of elixir and erlang can change via `asdf` whenever the user wants

Basicallly, the project's assets can change at any time, and it's not
guaranteed that the language server will be able to detect all of the
changes, so the language server needs to treat this cache with some
skepticism and constantly "check its work".

## Cache layout
A cache entry will have the following format:

```elixir

@type source :: Lexical.uri()
@entry_type :: :otp | :elixir | :dependency | :project

@type entry %{
  type: entry_type(),
  source: source(),
  entry_version: String.t(),
  added_at: DateTime.t(),
  value: term()
}
```

### Invalidation
When lexical starts the first time, it will need to index the
following entities in the following order:

  1. The elixir release
  2. All project dependencies
  3. The project's source code and built artifacts

The index needs to take into account which stage added it, and include an appropriate
version when adding an entry. The versions are as follows:

| Entry Type  | Entry Version |
| ----------- | --------------|
| :otp        | [This insanity](https://stackoverflow.com/questions/9560815/how-to-get-erlangs-release-version-number-from-a-shell/34326368#34326368)|
| :elixir     | `System.version()`|
| :dependency | `Application.spec(dep_atom)[:vsn]`|
| :project    | `md5(file contents)` |

Entries in the cache should be replaced and not updated, and we should
have a mechanism to sweep old entries from the cache (for example, if
a dependecy version is old and hasn't been updated in two weeks, we
should remove it). This invalidation is going to be one of the tricky
parts of the cache, and we should be aggressive with it, as
re-indexing things is likely to be less bad than having an
ever-growing cache on disk.  We need to think more about this and come
up with something that strikes a balance between efficiency and
on-disk storage.

# Indexing
Indexing and searching go hand-in-hand, you need to make an index in a
format that's useful, and as such, we'll approach this at a later
date. In the interim, we can probably get away with a linear search;
there aren't _that many_ things that we're indexing and elixir is kind
of fast for this kind of thing.

# Recognition
When we do things like "go to definition" or "find references" we need
to understand the context beneath the cursor to determine _what_ to
look for. However, this can be somewhat challenging, because elixir
has ambiguity in its syntax. For example:

```elixir
foo
```

can be a variable or a function call. Our recognition engine needs to
be able to distinguish between the two things. Looking at source code
isn't enough, the ambiguity will still be present in AST. We'd likely
need to look at the `__ENV__` of the file at that point and see if any
of the `functions`, `imported_macros` or `versioned_variables` have
the same name, and decide what it is based on that. This can be tricky
if the file doesn't compile. ElixirSense does a lot of the work for us
here, we might want to stick with it in the near future.
