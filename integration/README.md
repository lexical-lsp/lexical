# Integration tests

These integration tests confirm that Lexical can start using the correct version manager (asdf/rtx) and Elixir/Erlang versions in a variety of environments.
They work using a Docker image with both asdf and rtx installed, but with neither activated.
An individual test will then run some setup and manipulate the environment, then ensure that Lexical can properly start.

## Running the tests

Tests are run using `test.sh`:

```sh
$ ./integration/test.sh
```

By default, this will first build the Docker image and then run the tests.
The first run will take quite some time to build the image, but subsequent runs will be much faster, as most setup will be cached and only Lexical will need to be rebuilt.

If needed, you can separate building and running using `build.sh` and the `NO_BUILD=1` flag:

```sh
$ ./integration/build.sh
$ NO_BUILD=1 ./integration/test.sh
```

### Debugging

Run the tests with `LX_DEBUG=1` to see the output from the underlying commands:

```sh
$ LX_DEBUG=1 ./integration/test.sh
...
test_find_asdf_directory...
> No version manager detected
> Found asdf. Activating...
> Detected Elixir through asdf: /root/.asdf/installs/elixir/1.15.6-otp-26/bin/elixir
Pass
...
```
