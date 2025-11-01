{
  lib,
  lndir,
  stdenvNoCC,
  makeBinaryWrapper,
  neovim-unwrapped,
}:

let
  inherit (lib)
    getExe
    makeBinPath
    getVersion
    unique
    subtractLists
    concatLists
    optionalString
    concatMapStrings
    ;

  inherit (builtins) typeOf baseNameOf;
in

lib.extendMkDerivation {
  constructDrv = stdenvNoCC.mkDerivation;

  extendDrvArgs =
    _:
    {
      # neovim
      pname ? "neovim",
      versionSuffix ? "wrapped",

      # you can choose the base, i choose neovim-unwrapped
      basePackage ? neovim-unwrapped,

      # extra lua packages
      extraLuaPackages ? _: [ ],

      # path, see there explanation below
      extraPackages ? [ ],

      # providers, these are the providers that will be enabled
      providers ? { },

      # extra init.lua, this is useful for setting up the environment
      extraInitLua ? "",

      # plugins
      startPlugins ? [ ],
      optPlugins ? [ ],

      # our config
      userConfig,

      # other customisation
      aliases ? [ ],
      keepDesktopFiles ? false,
    }@args:
    let
      inherit (basePackage) lua;
      luaEnv = lua.withPackages extraLuaPackages;
      inherit (lua.pkgs) luaLib;

      # find deps
      # see https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/vim/plugins/utils/vim-utils.nix#L159-L164
      transitiveClosure =
        plugin: [ plugin ] ++ (lib.unique (concatLists (map transitiveClosure plugin.dependencies or [ ])));
      findDependenciesRecursively = plugins: lib.concatMap transitiveClosure plugins;

      depsOfOptionalPlugins = subtractLists optPlugins (findDependenciesRecursively optPlugins);
      startWithDeps = findDependenciesRecursively startPlugins;
      startPlugins' = unique (startWithDeps ++ depsOfOptionalPlugins);

      # i couldn't chose a nice api between attrs and lists, so i just did both lol
      attrsifiedProviders =
        if lib.isAttrs providers then providers else (lib.genAttrs providers (_: true));

      # merge providers attrs, with priority to the user providerd options
      pluginProviders = {
        node = false;
        perl = false;
        python = false;
        python3 = false;
        ruby = false;
      }
      // attrsifiedProviders;

      mkResultingPath =
        subdir: p:
        "pack/${pname}/${subdir}/${if typeOf p == "path" then baseNameOf p else (p.pname or p.name)}";

      config = stdenvNoCC.mkDerivation {
        name = "neovim-config";
        __structuredAttrs = true;

        plugins = startPlugins' ++ optPlugins;
        resultingPaths =
          map (mkResultingPath "start") startPlugins' ++ map (mkResultingPath "opt") optPlugins;

        # didn't know you could do this. thanks getchiee
        buildCommand =
          # bash
          ''
            mkdir -pv $out/parser
            mkdir -pv $out/pack/${pname}/{start,opt}

            echo "generating init.lua"
            cat > $out/init.lua <<EOF
            package.path = "${luaLib.genLuaPathAbsStr luaEnv};$LUA_PATH" .. package.path
            package.cpath = "${luaLib.genLuaCPathAbsStr luaEnv};$LUA_CPATH" .. package.cpath
            vim.env.PATH = vim.env.PATH .. ":${makeBinPath extraPackages}"
            vim.g.snippets_path = "$out/pack/${pname}/start/init-plugin/snippets"
            vim.opt.packpath:prepend('$out')
            vim.opt.runtimepath:prepend('$out')

            vim.loader.enable()

            ${lib.concatMapAttrsStringSep "\n" (provider: enabled: ''
              vim.g.loaded_${provider}_provider = ${if enabled then "1" else "0"}
            '') pluginProviders}

            ${extraInitLua}

            do
              vim.cmd.packadd({ "init-plugin", bang = true })
              local ok, result = pcall(require, '${pname}')
              if not ok then
                return
              end
            end
            EOF

            shopt -s extglob
            for (( i = 0; i < "''${#plugins[@]}"; i++ )); do
              source="''${plugins[$i]}"
              path="''${resultingPaths[$i]}"
              dest="$out/$path"

              if [[ -d "$dest" ]]; then
                echo "warning: destination '$dest' already exists, skipping"
                continue
              fi

              mkdir -p "$dest"

              tolink=("$source/"!(parser))
              if (( "''${#tolink[@]}" )); then
                ln -ns "''${tolink[@]}" -t "$dest"
              fi

              if [[ -d "$source/parser" && -n "$(ls -A "$source/parser")" ]]; then
                mkdir -p "$out/parser"
                ln -nsf "$source/parser/"* -t "$out/parser"
              fi
            done
            shopt -u extglob

            ${getExe basePackage} \
              -n -u NONE -i NONE \
              --headless \
              -c "set packpath=$out" \
              -c "packloadall" \
              -c "helptags ALL" \
              +"quit!"

            ln -sfT ${userConfig} $out/pack/${pname}/start/init-plugin

            find "$out/pack/${pname}" -type d -empty -print -delete

            mkdir "$out/nix-support"
            for i in $(find -L "$out" -name 'propagated-build-inputs'); do
              cat "$i" >> "$out/nix-support/propagated-build-inputs"
            done
          '';
      };
    in
    {
      inherit pname;
      version = "${args.version or (getVersion basePackage)}${
        if versionSuffix != "" then "-${versionSuffix}" else ""
      }";

      # don't allow for simple arugments here these **should** remain this way
      # so the wrapper works correctly
      __structuredAttrs = true;
      strictDeps = true;

      # this won't really remove anything since we still are running fixup on basePackage and the config
      # but it does speed up the build speed
      dontUnpack = true;
      dontFixup = true;
      dontConfigure = true;
      dontRewriteSymlinks = true;

      nativeBuildInputs = args.nativeBuildInputs or [ ] ++ [
        makeBinaryWrapper
        lndir
      ];

      wrapperArgs = [
        "--set-default"
        "VIMINIT"
        "source ${config}/init.lua"

        "--set-default"
        "NVIM_APPNAME"
        pname
      ]
      ++ args.wrapperArgs or [ ];

      installPhase = ''
        runHook preInstall

        mkdir -p $out
        lndir -silent ${basePackage} $out

        ${optionalString (!keepDesktopFiles) "rm -rf $out/share/applications"}

        wrapProgram $out/bin/nvim "''${wrapperArgs[@]}"

        ${concatMapStrings (alias: ''
          ln -s $out/bin/nvim $out/bin/${alias}
        '') aliases}

        runHook postInstall
      '';

      passthru = {
        inherit config;
      }
      // args.passthru or { };

      meta =
        basePackage.meta
        // {
          priority = (basePackage.meta.priority or lib.meta.defaultPriority) - 1;
        }
        // args.meta or { };
    };
}
