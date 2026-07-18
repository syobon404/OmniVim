{
  description = "OmniVim development and GPA GUI detector model conversion";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = function:
        nixpkgs.lib.genAttrs supportedSystems (system: function nixpkgs.legacyPackages.${system});
    in {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            python312
            uv
          ];

          shellHook = ''
            omnivim_venv="$PWD/.venv"
            omnivim_requirements="$PWD/Tools/ModelConversion/GPA/requirements.txt"
            omnivim_requirements_lock="$PWD/Tools/ModelConversion/GPA/requirements.lock"
            omnivim_stamp="$omnivim_venv/.omnivim-requirements.sha256"

            if [ ! -x "$omnivim_venv/bin/python" ]; then
              python -m venv "$omnivim_venv"
            fi

            source "$omnivim_venv/bin/activate"
            export UV_PROJECT_ENVIRONMENT="$omnivim_venv"

            omnivim_requirements_hash="$(cat "$omnivim_requirements" "$omnivim_requirements_lock" "$PWD/flake.nix" | shasum -a 256 | cut -d ' ' -f 1)"
            omnivim_installed_hash="$(test -f "$omnivim_stamp" && sed -n '1p' "$omnivim_stamp")"
            if [ "$omnivim_requirements_hash" != "$omnivim_installed_hash" ]; then
              uv pip sync "$omnivim_requirements_lock"
              echo "$omnivim_requirements_hash" > "$omnivim_stamp"
            fi

            echo "OmniVim model environment ready: $omnivim_venv"
          '';
        };
      });
    };
}
