{
  description = "rt-series — User-mode foreign Linux guest runtimes for AArch64 hosts and hyper-linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.gnumake
              pkgs.git
              pkgs.jq
              pkgs.python3
              pkgs.ripgrep
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
            for f in README.md AGENTS.md CLAUDE.md LICENSE SPEC.md PLAN.md GOAL.md docs/HOST-CONTRACT.md \
                     docs/lanes/wave-1-closeout.md docs/lanes/wave-2-rv32gc.md \
                     docs/lanes/wave-3-rt32-family.md docs/lanes/wave-4-rt64-family.md \
                     lode/README.md lode/STATE-OF-PLAY-2026-10-23.md lode/ISA-TRAP-AND-ABI-MATRIX.md \
                     lode/reviews/2026-10-23-astra-review-1.md \
                     lode/reviews/2026-10-23-astra-review-1-dispositions.md \
                     lode/reviews/2026-10-23-astra-review-2.md \
                     lode/reviews/2026-10-23-astra-review-2-dispositions.md \
                     tests/check_abi_invariants.c; do
              test -s "${self}/$f"
            done
            mkdir -p "$out"
            echo "OK" > "$out/status"
          '';
        }
      );
    };
}
