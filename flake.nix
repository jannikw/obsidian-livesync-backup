{
  description = "A very basic flake";

  inputs = {
    # self.submodules = true;
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      deps = pkgs.stdenv.mkDerivation {
        name = "deps";
        src = ./.;
        buildInputs = [ pkgs.deno ];
        XDG_CACHE_HOME="/tmp/deno"; 
        buildPhase =''
          echo $HOME
          deno cache main.ts
          ls -la

          mkdir $out
          mv node_modules/ vendor/ $out
        '';

         outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        outputHash = "sha256-Om4BcXK76QrExnKcDzw574l+h75C8yK/EbccpbcvLsQ=";
      };
    in
    {
      packages.${system}.default = deps;

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ pkgs.deno ];
      };
    };
}
