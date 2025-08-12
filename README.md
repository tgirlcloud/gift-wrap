## Gift Wrap

Gift wrap is a simple neovim wrapper for nix that allows you to maintain your
neovim configuration with lua and with nix for package management. As gift wrap
is ment to be a very minimal neovim wrapper, it abstracts very little, and is
based off of the nixpkgs wrapper but with some personalized tweaks.

### Usage

```nix
{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";

    gift-wrap = {
      url = "github:tgirlcloud/gift-wrap";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, gift-wrap }:
    let
      inherit (nixpkgs) lib;

      forAllSystems =
        f: lib.genAttrs lib.systems.flakeExposed (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        nvim = gift-wrap.legacyPackages.${pkgs.system}.wrapNeovim {
          # what is the name of your neovim config?
          pname = "my-neovim";

          # perhaps add a version suffix to your package
          # this is a sensible default
          versionSuffix = self.shortRev or self.dirtyShortRev or "unknown";

          # this is the base package for your neovim configuration
          # this defaults to neovim-unwrapped and most of the time you will not need to change this
          basePackage = pkgs.neovim-unwrapped;

          # this field allows you to create aliases to the neovim executable
          # this defaults to blank, the bellow example will create the aliases `vi` and `vim`
          aliases = [ "vi" "vim" ];

          # wether to keep the desktop files for neovim
          # by default this is set to false, but you can set it to true
          keepDesktopFiles = true;

          # your user conifguration, this should be a path your nvim config in lua
          userConfig = ./config;

          # all the plugins that should be stored in the neovim start directory
          # these are the plugins that are loaded when neovim starts
          startPlugins = with pkgs.vimPlugins; [
            nvim-treesitter.withAllGrammars
            nvim-lspconfig
          ];

          # these are plugins that are loaded on demand by your configuration
          optPlugins = with pkgs.vimPlugins; [
            blink-cmp
            telescope
            lazygit-nvim
          ];

          # these are any extra packages that should be available in your neovim environment
          extraPackages = with pkgs; [
            ripgrep
            fd
            inotify-tools
            lazygit
          ];

          # below is a list of plugin providers, these should then be
          # configured in your plugin or setup properly by adding to your path
          # or the extraInitLua
          #
          # this can also be a list of strings
          providers = {
            node = false;
            python = false;
            python3 = true;
            ruby = false;
            perl = false;
          };

          # following the providers above, you can set the exact package for
          # your providers, in this case python3
          extraInitLua = ''
            vim.g.python3_host_prog = '${lib.getExe pkgs.python3}'
          '';
        };
      });
    };
}
```
