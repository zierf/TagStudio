{
  description = "TagStudio";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Pinned to Qt version 6.7.1
    nixpkgs-qt6.url = "github:NixOS/nixpkgs/e6cea36f83499eb4e9cd184c8a8e823296b50ad5";

    systems.url = "github:nix-systems/default-linux";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = { self, nixpkgs, flake-utils, ... } @inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs) lib;

        qt6Pkgs = import inputs.nixpkgs-qt6 { inherit system; };

        # see https://github.com/nix-community/poetry2nix/tree/master#api for more functions and examples.
        pkgs = nixpkgs.legacyPackages.${system}.extend inputs.poetry2nix.overlays.default;

        # override some missing dependencies for python packages
        # https://github.com/nix-community/poetry2nix/blob/8ffbc64abe7f432882cb5d96941c39103622ae5e/docs/edgecases.md#modulenotfounderror-no-module-named-packagename
        pypkgs-build-requirements = {
          #python-xlib = [ "setuptools" "setuptools-scm" ];
        };
        p2n-overrides = pkgs.poetry2nix.defaultPoetryOverrides.extend (self: super:
          builtins.mapAttrs
            (package: build-requirements:
              (builtins.getAttr package super).overridePythonAttrs (old: {
                buildInputs = (old.buildInputs or [ ]) ++ (builtins.map (pkg: if builtins.isString pkg then builtins.getAttr pkg super else pkg) build-requirements);
              })
            )
            pypkgs-build-requirements
        );

        inherit (inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; }) mkPoetryApplication;

        tagstudioApp = mkPoetryApplication rec {
          projectDir = self;

          # editablePackageSources = {
          #   tagstudio = ./tagstudio;
          # };

          python = pkgs.python312;
          preferWheels = false;

          overrides = p2n-overrides.extend
            # https://github.com/nix-community/poetry2nix/blob/7619e43/docs/edgecases.md#modulenotfounderror-no-module-named-packagename
            (final: prev: {
              pyside6-essentials = prev.pyside6-essentials.overridePythonAttrs (
                old: {
                  # prevent error: "Error: wrapQtAppsHook is not used, and dontWrapQtApps is not set."
                  dontWrapQtApps = true;

                  # satisfy some missing auto-patchelf libraries for PySide6-Essentials
                  buildInputs = (old.buildInputs ++ (with qt6Pkgs; [
                    qt6.qtquick3d
                    qt6.qtvirtualkeyboard
                    qt6.qtwebengine
                  ]))
                  ++ [ ];
                }
              );
            });

          pythonRelaxDeps = [ ];

          additionalPackages = (with pkgs; [
            # python312.pkgs.pyside6
            dbus
            fontconfig
            freetype
            glib
            libGL
            libkrb5
            libpulseaudio
            libva
            libxkbcommon
            # mesa contains libgbm
            # mesa
            openssl
            stdenv.cc.cc.lib
            wayland
            xorg.libxcb
            xorg.libXrandr
            # QT 6.7.0
            # zstd
          ])
          ++ (with qt6Pkgs; [
            # `qt6.full` prevents error on KDE systems:
            # "Cannot mix incompatible Qt library (6.7.2) with this library (6.7.1)""
            qt6.full
            # qt6.qtquick3d
            # qt6.qtvirtualkeyboard
            # qt6.qtwebengine
          ]);

          nativeBuildInputs = (with pkgs; [
            makeWrapper
          ])
          ++ (with qt6Pkgs; [
            qt6.qtbase
            qt6.wrapQtAppsHook
          ])
          ++ additionalPackages;

          buildInputs = with pkgs; [ ] ++ additionalPackages;

          propogatedBuildInputs = with pkgs; [
            # mesa
            # python312.pkgs.pyside6
            # qt6.qtquick3d
            # qt6.qtvirtualkeyboard
            # qt6.qtwebengine
          ] ++ additionalPackages;

          LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;

          # dontWrapQtApps = true;

          # preFixup = ''
          #   wrapQtApp "$out/bin/tagstudio_dev" --prefix PATH : /path/to/bin
          # '';
        };
      in
      {
        # $> nix build .
        packages = {
          tagstudio = tagstudioApp;
          default = tagstudioApp;
        };

        # Shell for app dependencies.
        # $> nix develop
        #
        # Use this shell for developing your app.
        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.tagstudio ];
        };

        # Shell for poetry.
        # $> nix develop .#poetry
        #
        # Use this shell for changes to pyproject.toml and poetry.lock.
        #   - Run `poetry install to generate an inital lock file.
        #   - Run `poetry lock` after changing dependencies.
        #   - Run `poetry run tagstudio` to execute the application.
        devShells.poetry = pkgs.mkShell rec {
          packages = with pkgs; [
            poetry
            cmake
            mypy
            ruff
          ] ++ (with qt6Pkgs; [
            qtcreator
          ])
          ++ tagstudioApp.additionalPackages;

          LD_LIBRARY_PATH = lib.makeLibraryPath packages;
        };
      });
}
