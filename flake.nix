{
  description = "Obsidian Livesync Backup";

  inputs = {
    self.submodules = true;
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      deno = pkgs.deno;

      appDepenencies = pkgs.stdenv.mkDerivation {
        name = "deps";
        src = ./.;
        buildInputs = [ deno ];
        XDG_CACHE_HOME="/tmp/deno"; 
        buildPhase =''
          deno cache main.ts

          mkdir $out
          mv node_modules/ vendor/ $out

          mkdir $out/cache
          mv $XDG_CACHE_HOME/deno/npm $out/cache
        '';

        outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        outputHash = "sha256-y6k7k08gNODswqLi9JEsHpvMX5sbiVeaRyUlmV1WaWo=";
      };
      deno-runtime = pkgs.fetchurl {
        url = "https://dl.deno.land/release/${deno.version}/denort-x86_64-unknown-linux-gnu.zip";
        sha256 = "sha256-RRCmEgOSoMuRZRlD+rEELz56wv3q62pzs9AhSWYzFzM=";
      };
      app = pkgs.stdenv.mkDerivation {
        name = "livesync-backup";
        src = ./.;
        buildInputs = [ pkgs.deno ];
        XDG_CACHE_HOME="/tmp/deno"; 
        buildPhase = ''
          # Restore the cached dependencies
          mkdir -p $XDG_CACHE_HOME/deno
          ln -s "${appDepenencies}/cache/npm" $XDG_CACHE_HOME/deno/npm
          ln -s "${appDepenencies}/vendor" vendor
          ln -s "${appDepenencies}/node_modules" node_modules

          mkdir -p $XDG_CACHE_HOME/deno/dl/release/v${pkgs.deno.version}
          ln -s ${deno-runtime} $XDG_CACHE_HOME/deno/dl/release/v${pkgs.deno.version}/denort-x86_64-unknown-linux-gnu.zip

          mkdir -p $out/bin
          deno compile --vendor \
           --node-modules-dir=auto \
           --cached-only --no-check \
           --output $out/bin/livesync-backup \
           --target=x86_64-unknown-linux-gnu \
           --allow-all \
           main.ts
        '';

        # Patching the binary seems to break some self extracting mechanism.
        dontAutoPatchELF = true;
        dontStrip = true;
      };
      # Found no easy way to get a binary compiled with Deno to run on NixOS.
      # So we wrap it in a FHS environment.
      appWrappedWithEnv = pkgs.buildFHSEnv {
        name = "livesync-backup";
        runScript = "${app}/bin/livesync-backup";
      };
    in
    {
      packages.${system}.default = appWrappedWithEnv;

      nixosModules.default = import ./nixos-module.nix {
        obsidian-livesync-backup = self.packages.${system}.default;
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ pkgs.deno ];
      };
    };
}
