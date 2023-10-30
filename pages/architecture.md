# Architecture

## Project Structure
Lexical is designed to keep your application isolated from lexical's code. Because of this, lexical is structured as an umbrella app, with the following sub-apps:

  * `core`: Contains all code common to the other applications.
  * `protocol`: Code related to speaking the language server protocol.
  * `remote_control`: The application that's injected into a project's code, which
     gives lexical an API to do things in the context of your app. 
  * `server` The language server itself.

Lexical is an umbrella app so we can control how many dependencies the remote control app has. By separating lexical into sub-applications, each is built as a separate archive, and we can pick and choose which of these applications (and their dependencies) are injected into the project's VM, thus reducing how much contamination the project sees. If lexical was a standard application, adding dependencies to lexical would cause those dependencies to appear in the project's VM, which might cause build issues, version conflicts in mix or other inconsistencies.
 
Since the `remote_control` app only depends on `common`, `path_glob` and `elixir_sense`, only those applications pollute the project's vm. Keeping `remote_control`'s dependencies to a minimum is a design goal of this architecture.


## Language Server
The language server (the `server` app) is the entry point to Lexical. When started by the `start_lexical.sh` command, it sets up a [transport](`Lexical.Server.Transport`) that [reads JsonRPC from standard input and writes responses to standard output](`Lexical.Server.Transport.StdIO`). 

When a message is received, it is parsed into either a [LSP Request](`Lexical.Protocol.Requests`) or a [LSP Notification](`Lexical.Protocol.Notifications`) and then it's handed to the [language server](`Lexical.Server`) to process.

The only messages the [lexical server process](`Lexical.Server`) handles directly are those related to the lifecycle of the language server itself. All other messages are delegated to a _Provider Handler_. This delegation is accomplished by the server process adding the request to the [provider queue](`Lexical.Server.Provider.Queue`). The provider queue asks the `Lexical.Server.Provider.Handlers.for_request/1` function which handler is configured to handle the request, creates a task for the handler and starts it.

A _Provider Handler_ is just a module that defines a function of arity 2 that takes the request to handle and a `Lexical.Server.Provider.Env`. These functions can reply to the request, ignore it, or do some other action. 

