{
  description = "Reimagined language server for Elixir";

  inputs.nixpkgs.url = "flake:nixpkgs";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.systems.url = "github:nix-systems/default";

  outputs = {
    self,
    nixpkgs,
    systems,
    ...
  } @ inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import systems;

      perSystem = {
        self',
        pkgs,
        ...
      }: let
        erl = pkgs.beam.packages.erlang;
        lexical = erl.callPackage ./nix/lexical.nix {};
      in {
        formatter = pkgs.alejandra;

        packages = {
          inherit lexical;
          default = lexical;

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
      };
    };
}
