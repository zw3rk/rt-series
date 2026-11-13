# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0
{
  description = "rt-series — Umbrella flake for the zw3rk family of 10 foreign-Linux user-mode binary translators targeting AArch64 hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    a32rt = {
      url = "github:zw3rk/a32rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    i686rt = {
      url = "github:zw3rk/i686rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mips32rt = {
      url = "github:zw3rk/mips32rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ppc32rt = {
      url = "github:zw3rk/ppc32rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sparc32rt = {
      url = "github:zw3rk/sparc32rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rvrt = {
      url = "github:zw3rk/rvrt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    loongarch64rt = {
      url = "github:zw3rk/loongarch64rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ppc64rt = {
      url = "github:zw3rk/ppc64rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mips64rt = {
      url = "github:zw3rk/mips64rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sparc64rt = {
      url = "github:zw3rk/sparc64rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    a32rt,
    i686rt,
    mips32rt,
    ppc32rt,
    sparc32rt,
    rvrt,
    loongarch64rt,
    ppc64rt,
    mips64rt,
    sparc64rt,
    ...
  }:
    let
      supportedSystems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          translators = {
            a32rt         = a32rt.packages.${system}.a32rt;
            i686rt        = i686rt.packages.${system}.i686rt;
            mips32rt      = mips32rt.packages.${system}.mips32rt;
            ppc32rt       = ppc32rt.packages.${system}.ppc32rt;
            sparc32rt     = sparc32rt.packages.${system}.sparc32rt;
            rvrt          = rvrt.packages.${system}.rvrt-linux-aarch64;
            rvrt-inspect  = rvrt.packages.${system}.default;
            loongarch64rt = loongarch64rt.packages.${system}.loongarch64rt;
            ppc64rt       = ppc64rt.packages.${system}.ppc64rt;
            mips64rt      = mips64rt.packages.${system}.mips64rt;
            sparc64rt     = sparc64rt.packages.${system}.sparc64rt;
          };
          mkDarwinTranslator = name: src: makeTarget: binRel:
            pkgs.clangStdenv.mkDerivation {
              pname = "${name}-darwin";
              version = "0.1.0";
              inherit src;
              nativeBuildInputs = [ pkgs.gnumake pkgs.coreutils ];
              dontConfigure = true;
              buildPhase = "make ${makeTarget}";
              installPhase = ''
                mkdir -p $out/bin
                install -m0755 ${binRel} $out/bin/${name}-darwin
                ln -sf ${name}-darwin "$out/bin/${name}-darwin-arm64"
              '';
            };
          darwinTranslators =
            if system == "aarch64-darwin" then
              let
                darwinPkgs = {
                  a32rt-darwin         = mkDarwinTranslator "a32rt" a32rt "build-darwin" "_build/a32rt-darwin";
                  i686rt-darwin        = mkDarwinTranslator "i686rt" i686rt "_build/i686rt-darwin" "_build/i686rt-darwin";
                  mips32rt-darwin      = mkDarwinTranslator "mips32rt" mips32rt "build-darwin" "_build/mips32rt-darwin";
                  ppc32rt-darwin       = mkDarwinTranslator "ppc32rt" ppc32rt "build-darwin" "_build/ppc32rt-darwin";
                  sparc32rt-darwin     = mkDarwinTranslator "sparc32rt" sparc32rt "build-darwin" "_build/sparc32rt-darwin";
                  rvrt-darwin          = mkDarwinTranslator "rvrt" rvrt "-j8 HOST_LIBTOOL=${pkgs.darwin.cctools}/bin/libtool _build/rvrt-darwin-arm64" "_build/rvrt-darwin-arm64";
                  loongarch64rt-darwin = mkDarwinTranslator "loongarch64rt" loongarch64rt "DARWIN_CC=clang build-darwin" "_build/loongarch64rt-darwin-arm64";
                  ppc64rt-darwin       = mkDarwinTranslator "ppc64rt" ppc64rt "_build/ppc64rt-darwin" "_build/ppc64rt-darwin";
                  mips64rt-darwin      = mkDarwinTranslator "mips64rt" mips64rt "_build/mips64rt-darwin" "_build/mips64rt-darwin";
                  sparc64rt-darwin     = mkDarwinTranslator "sparc64rt" sparc64rt "DARWIN_TARGET=arm64-apple-darwin build-darwin" "_build/sparc64rt-darwin-arm64";
                };
                all-translators-darwin = pkgs.symlinkJoin {
                  name = "rt-series-all-translators-darwin-0.1.0";
                  paths = [
                    darwinPkgs.a32rt-darwin
                    darwinPkgs.i686rt-darwin
                    darwinPkgs.mips32rt-darwin
                    darwinPkgs.ppc32rt-darwin
                    darwinPkgs.sparc32rt-darwin
                    darwinPkgs.rvrt-darwin
                    darwinPkgs.loongarch64rt-darwin
                    darwinPkgs.ppc64rt-darwin
                    darwinPkgs.mips64rt-darwin
                    darwinPkgs.sparc64rt-darwin
                  ];
                };
              in darwinPkgs // { inherit all-translators-darwin; }
            else { };
          all-translators = pkgs.symlinkJoin {
            name = "rt-series-all-translators-0.1.0";
            paths = [
              translators.a32rt
              translators.i686rt
              translators.mips32rt
              translators.ppc32rt
              translators.sparc32rt
              translators.rvrt
              translators.loongarch64rt
              translators.ppc64rt
              translators.mips64rt
              translators.sparc64rt
            ] ++ nixpkgs.lib.optionals (system == "aarch64-darwin") [
              darwinTranslators.all-translators-darwin
            ];
          };
        in translators // darwinTranslators // {
          inherit all-translators;
          default = all-translators;
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          a64Musl = pkgs.pkgsCross.aarch64-multiplatform-musl;
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.gnumake
              pkgs.git
              pkgs.jq
              pkgs.python3
              pkgs.ripgrep
              a64Musl.stdenv.cc
            ];
          };
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          docs-and-headers = pkgs.runCommand "rt-series-check" {
            nativeBuildInputs = [ pkgs.clang pkgs.python3 ];
          } ''
            clang -std=c11 -Wall -Wextra -Werror=vla -pedantic -fsyntax-only ${self}/include/a32host.h
            clang -std=c11 -Wall -Wextra -Werror=vla -pedantic -I${self}/include \
              -o ./check_abi_invariants ${self}/tests/check_abi_invariants.c
            ./check_abi_invariants
            for f in README.md AGENTS.md CLAUDE.md LICENSE include/a32host.h tests/check_abi_invariants.c \
                     docs/ARCHITECTURE.md docs/DEFECTS.md docs/HOST-CONTRACT.md docs/FEATURE-MATRIX.md \
                     docs/SOFTWARE-CATALOGUE.md docs/CONVERGENCE-AUDIT-PROCESS.md \
                     docs/archive/plans/SPEC.md docs/archive/plans/PLAN.md docs/archive/plans/UNIFICATION-PLAN.md \
                     docs/archive/defects/rounds-01-12.md docs/archive/defects/rounds-13-18.md \
                     lode/README.md lode/ISA-TRAP-AND-ABI-MATRIX.md; do
              test -s "${self}/$f"
            done
            mkdir -p "$out"
            echo "OK" > "$out/status"
          '';
          a32rt         = self.packages.${system}.a32rt;
          i686rt        = self.packages.${system}.i686rt;
          mips32rt      = self.packages.${system}.mips32rt;
          ppc32rt       = self.packages.${system}.ppc32rt;
          sparc32rt     = self.packages.${system}.sparc32rt;
          rvrt          = self.packages.${system}.rvrt;
          loongarch64rt = self.packages.${system}.loongarch64rt;
          ppc64rt       = self.packages.${system}.ppc64rt;
          mips64rt      = self.packages.${system}.mips64rt;
          sparc64rt     = self.packages.${system}.sparc64rt;
        }
      );

      hydraJobs = forAllSystems (system: {
        inherit (self.packages.${system})
          a32rt
          i686rt
          mips32rt
          ppc32rt
          sparc32rt
          rvrt
          loongarch64rt
          ppc64rt
          mips64rt
          sparc64rt
          all-translators;
        docs-and-headers = self.checks.${system}.docs-and-headers;
      });
    };
}
