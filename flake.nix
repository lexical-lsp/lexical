{
  description = "Reimagined language server for Elixir";

  inputs.nixpkgs.url = "flake:nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs =
    { self
    , nixpkgs
    , flake-utils
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        erl = pkgs.beam.packages.erlang;
        lexical = erl.callPackage ./nix/lexical.nix {};
      in
      {
        packages = {
          inherit lexical;

          default = lexical;

          # Private package used to automatically generate hash for Mix deps
          __fodHashGen = lexical.mixFodDeps.overrideAttrs(final: curr: {
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
