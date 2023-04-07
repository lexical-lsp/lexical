# Lexical

Lexical is a next-generation language server for the Elixir programming language.

## Features

  * Code Completion
  * As-you-type compilation
  * Advanced error highlighting
  * Code actions
  * Code Formatting
  * Completely isolated build environment
  
## Installation
To install lexical fetch the source code from git, then do the following:

 ```
 mix deps.get
 mix deps.compile
 MIX_ENV=prod mix release lexical
 ```
 
 Lexical will now be available in `_build/prod/rel/lexical`
 
To use lexical as a language server while working on lexical source code,
use the following to produce the release and avoid bugs:

 ```
 NAMESPACE=1 mix release lexical
 ```

