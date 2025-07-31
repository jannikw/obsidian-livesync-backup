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
      deps = pkgs.stdenv.mkDerivation {
        name = "deps";
        src = ./.;
        buildInputs = [ pkgs.deno ];
        XDG_CACHE_HOME="/tmp/deno"; 
        buildPhase =''
          echo $HOME
          deno cache main.ts
          deno info
          ls -la

          mkdir $out
          mv node_modules/ vendor/ $out

          mkdir $out/cache
          ls -lar $XDG_CACHE_HOME/deno
          mv $XDG_CACHE_HOME/deno/npm $out/cache
          # mv $XDG_CACHE_HOME/deno/remote $out/cache
        '';

         outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        outputHash = "sha256-tUMd5MyZ8NYKGdoDXIgo9XTTFqjXs2iaXhyRGkEPnuU=";
      };
      denort = pkgs.fetchurl {
        url = "https://dl.deno.land/release/v2.2.2/denort-x86_64-unknown-linux-gnu.zip";
        sha256 = "sha256-RRCmEgOSoMuRZRlD+rEELz56wv3q62pzs9AhSWYzFzM=";
      };
      app = pkgs.stdenv.mkDerivation {
        name = "livesync-backup";
        src = ./.;
        buildInputs = [ pkgs.deno pkgs.hexdump pkgs.xxd ];
        XDG_CACHE_HOME="/tmp/deno"; 

        nativeBuildInputs = [ pkgs.makeWrapper ];


        buildPhase = ''
          mkdir -p $XDG_CACHE_HOME/deno
          ln -s "${deps}/cache/npm" $XDG_CACHE_HOME/deno/npm

          mkdir -p $XDG_CACHE_HOME/deno/dl/release/v${pkgs.deno.version}
          ln -s ${denort} $XDG_CACHE_HOME/deno/dl/release/v${pkgs.deno.version}/denort-x86_64-unknown-linux-gnu.zip

          ln -s "${deps}/vendor" vendor
          ln -s "${deps}/node_modules" node_modules
          ls -la

          mkdir -p $out/bin
          deno compile --vendor \
           --node-modules-dir=auto \
           --cached-only --no-check \
           --output $out/bin/livesync-backup \
           --target=x86_64-unknown-linux-gnu \
           --allow-all \
           main.ts

          # TRAILER=$(tail -c 40 $out/bin/livesync-backup | hexdump -v -e '1/1 "%02x "')
          # patchelf --set-interpreter $(cat $NIX_CC/nix-support/dynamic-linker) $out/bin/livesync-backup
          # echo "$TRAILER" | xxd -r -p >> "$out/bin/livesync-backup"
        '';

        dontAutoPatchELF = true;
        dontStrip = true;
        # https://github.com/denoland/deno/issues/19961
        # installPhase = ''
        #   # since we can't patchelf, we need to ensure the dynamic linker
        #   # is where we expect it. This gets droppped into the rootfs as
        #   # /lib64/ld-linux-x86-64.so.2 -> /nix/store/*/ld-linux-x86-64.20.2
        #   mkdir -p $out/lib64
        #   ln -sf ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 $out/lib64/ld-linux-x86-64.so.2
        #   wrapProgram $out/bin/livesync-backup \
        #     --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath [
        #       pkgs.glibc
        #       pkgs.gcc-unwrapped.lib
        #     ]}" \
        #     --set SI_LANG_JS_LOG "debug" \
        #     --run 'cd "$(dirname "$0")"'
        #     # ^ deno falls over trying to resolve libraries if you don't set
        #     # the working path when executed by cyclone
        # '';
      };

      # steam-run "result/bin/livesync-backup"
      env = pkgs.buildFHSEnv {
        name = "livesync-backup";
        runScript = "${app}/bin/livesync-backup";
      };
    in
    {
      packages.${system}.default = env;

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ pkgs.deno ];
      };
    };
}
