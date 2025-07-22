{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      inherit (nixpkgs) lib;

      forAllSystems =
        f: lib.genAttrs lib.systems.flakeExposed (system: f nixpkgs.legacyPackages.${system});

      mkPkgs = pkgs: import ./default.nix { inherit pkgs; };
    in
    {
      formatter = forAllSystems (
        pkgs:
        pkgs.treefmt.withConfig {
          runtimeInputs = with pkgs; [
            # keep-sorted start
            deadnix
            keep-sorted
            nixfmt-rfc-style
            statix
            stylua
            taplo
            # keep-sorted end

            (writeShellScriptBin "statix-fix" ''
              for file in "$@"; do
                ${lib.getExe statix} fix "$file"
              done
            '')
          ];

          settings = {
            on-unmatched = "info";
            tree-root-file = "flake.nix";

            formatter = {
              # keep-sorted start block=yes newline_separated=yes
              deadnix = {
                command = "deadnix";
                includes = [ "*.nix" ];
              };

              keep-sorted = {
                command = "keep-sorted";
                includes = [ "*" ];
              };

              nixfmt = {
                command = "nixfmt";
                includes = [ "*.nix" ];
              };

              statix = {
                command = "statix-fix";
                includes = [ "*.nix" ];
              };
              # keep-sorted end
            };
          };
        }
      );

      legacyPackages = forAllSystems mkPkgs;
      packages = forAllSystems mkPkgs;
      overlays.default = _: mkPkgs;

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          inputsFrom = [
            self.formatter.${pkgs.stdenv.hostPlatform.system}
          ];
        };
      });
    };
}
