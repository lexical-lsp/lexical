# Remote Control

What's `RemoteControl` responsible for?
- Indexing your project, parsing it for the definitions of modules, functions, macros, and variables.
- Persisting these definitions into :ets in a format they can readily be queried and retrieved.

- The store can be queried with the following methods:
  - `exact/2`
  - `fuzzy/2`
  - `parent/1`
  - `prefix/2`
  - `siblings/1`

Why use ets as the backend for ?
- ets runs natively in Elixir, and there's no serialization overhead for retrieving terms stored in it.
