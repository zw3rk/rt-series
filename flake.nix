# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0
{
  description = "rt-series — Umbrella flake for the zw3rk family of 10 foreign-Linux user-mode binary translators targeting AArch64 hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    a32rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/a32rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    i686rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/i686rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mips32rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/mips32rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ppc32rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/ppc32rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sparc32rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/sparc32rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rvrt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/rvrt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    loongarch64rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/loongarch64rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ppc64rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/ppc64rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mips64rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/mips64rt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sparc64rt = {
      url = "git+file:///Users/angerman/Projects/zw3rk/sparc64rt";
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
            ];
          };
        in translators // {
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
            for f in README.md AGENTS.md CLAUDE.md LICENSE SPEC.md PLAN.md GOAL.md DEFECTS.md \
                     docs/HOST-CONTRACT.md docs/UNIFICATION-PLAN.md docs/FEATURE-MATRIX.md \
                     docs/CONVERGENCE-AUDIT-PROCESS.md \
                     docs/lanes/wave-1-closeout.md docs/lanes/wave-2-rv32gc.md \
                     docs/lanes/wave-3-rt32-family.md docs/lanes/wave-4-rt64-family.md \
                     lode/README.md lode/STATE-OF-PLAY-2026-10-23.md lode/ISA-TRAP-AND-ABI-MATRIX.md \
                     tests/check_abi_invariants.c; do
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
