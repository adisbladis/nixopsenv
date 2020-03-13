{ pkgs ? import <nixpkgs> {} }:

let

  overrides = import ./overrides.nix { inherit pkgs; };

  env = pkgs.poetry2nix.mkPoetryEnv {
    projectDir = ./.;
    overrides = pkgs.poetry2nix.overrides.withDefaults(overrides);
  };

in env
