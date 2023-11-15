{
  description = "Reimagined language server for Elixir";

  inputs.nixpkgs.url = "flake:nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        # little hack as we can't use `pkgs.system` yet
        is_darwin = system == "aarch64-darwin" || system == "x86_64-darwin";
        pkgs = import nixpkgs {inherit system;};
        inherit (pkgs.beam) packagesWith;
        inherit (pkgs.beam.interpreters) erlang;
        # yeah, it will take a long time to build...
        # nedeed because macOS sonoma breaks the JIT
        # reference: https://elixirforum.com/t/bus-error-after-upgrading-to-sonoma-beta/56354/44
        # another option is to use erlang/OTP >= 23.3.2.7 which disables JIT automatically on macOS
        darwin_override_erl = erlang.overrideAttrs (old: {
          configureFlags = old.configureFlags ++ ["--disable-jit"];
        });

        erl =
          if is_darwin
          then darwin_override_erl
          else erlang;

        erl' = packagesWith erl;
        lexical = erl'.callPackage ./nix/lexical.nix {};
      in {
        packages = {
          inherit lexical;

          default = lexical;

          # Private package used to automatically generate hash for Mix deps
          __fodHashGen = lexical.mixFodDeps.overrideAttrs (final: curr: {
            outputHash = pkgs.lib.fakeSha256;
          });
        };

        devShells.default = pkgs.mkShell {
          packages =
            [
              erl.elixir
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.darwin.apple_sdk.frameworks.CoreFoundation
              pkgs.darwin.apple_sdk.frameworks.CoreServices
            ];
        };
      }
    );
}
