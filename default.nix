{
  pkgs ? import <nixpkgs> {}
  , lib ? pkgs.lib
}:

let
  inherit (pkgs) poetry2nix symlinkJoin;

  # Wrap the buildEnv derivation in an outer derivation that omits interpreters & other binaries
  mkPluginDrv = {
    finalDrv
    , interpreter
    , plugins
  }: let

    # The complete buildEnv drv
    buildEnvDrv = interpreter.buildEnv.override {
      extraLibs = plugins;
    };

    # Create a separate environment aggregating the share directory
    # This is done because we only want /share for the actual plugins
    # and not for e.g. the python interpreter and other dependencies.
    manEnv = pkgs.symlinkJoin {
      name = "${finalDrv.pname}-with-plugins-share-${finalDrv.version}";
      preferLocalBuild = true;
      allowSubstitutes = false;
      paths = plugins;
      postBuild = ''
        if test -e $out/share; then
          mv $out out
          mv out/share $out
        else
          rm -r $out
          mkdir $out
        fi
      '';
    };

  in pkgs.runCommandNoCC "${finalDrv.pname}-with-plugins-${finalDrv.version}" {
    inherit (finalDrv) passthru meta;
  } ''
    mkdir -p $out/bin

    for bindir in ${lib.concatStringsSep " " (map (d: "${lib.getBin d}/bin") plugins)}; do
      for bin in $bindir/*; do
        ln -s ${buildEnvDrv}/bin/$(basename $bin) $out/bin/
      done
    done

    ln -s ${manEnv} $out/share
  '';

  # Make a python derivation pluginable
  #
  # This adds a `withPlugins` function that works much like `withPackages`
  # except it only links binaries from the explicit derivation /share
  # from any plugins
  toPluginAble = {
    drv
    , finalDrv
    , self
    , super
  }: drv.overridePythonAttrs(old: {
    passthru = old.passthru // {
      withPlugins = pluginFn: mkPluginDrv {
        plugins = [ finalDrv ] ++ pluginFn self;
        inherit finalDrv;
        inherit interpreter;
      };
    };
  });


  interpreter = (
    poetry2nix.mkPoetryPackages {
      projectDir = ./.;
      overrides = [
        poetry2nix.defaultPoetryOverrides
        (import ./overrides.nix { inherit pkgs; })
        # Attach meta to nixops
        (
          self: super: {
            nixops = super.nixops.overridePythonAttrs (
              old: {
                format = "pyproject";
                buildInputs = old.buildInputs ++ [
                  self.poetry
                ];
                meta = old.meta // {
                  homepage = https://github.com/NixOS/nixops;
                  description = "NixOS cloud provisioning and deployment tool";
                  maintainers = with lib.maintainers; [ aminechikhaoui eelco rob domenkozar ];
                  platforms = lib.platforms.unix;
                  license = lib.licenses.lgpl3;
                };

              }
            );
          }
        )
        # Make nixops pluginable
        (self: super: {
          nixops = toPluginAble {
            drv = super.nixops;
            finalDrv = self.nixops;
            inherit self super;
          };
        })
      ];
    }
  ).python;

in interpreter.pkgs.nixops
