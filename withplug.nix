let
  pkgs = import <nixpkgs> {};

  nixops = import ./default.nix { inherit pkgs; };
in
(
  nixops.withPlugins (
    ps: [
      ps.nixopsaws
    ]
  )
)
