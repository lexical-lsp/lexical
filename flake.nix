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
        pkgs = import nixpkgs {inherit system;};
        inherit (pkgs.beam.packages) erlang_26;

        mkLexical = {erlang}: erlang.callPackage ./nix/lexical.nix {};
      in rec {
        overlay = _final: _prev: {
          inherit mkLexical;
          inherit (packages) lexical;
        };
        packages = rec {
          lexical = mkLexical {erlang = erlang_26;};
          default = lexical;
          # Private package used to automatically generate hash for Mix deps
          __fodHashGen = lexical.mixFodDeps.overrideAttrs (final: curr: {
            outputHash = pkgs.lib.fakeSha256;
          });
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs;
            [erlang_26.elixir]
            ++ lib.optionals pkgs.stdenv.isDarwin [
              darwin.apple_sdk.frameworks.CoreFoundation
              darwin.apple_sdk.frameworks.CoreServices
            ];
        };
      }
    );
}
