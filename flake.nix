{
    inputs = {
        nixpkgs.url = "nixpkgs/nixos-unstable";
        flake-parts.url = "github:hercules-ci/flake-parts";
    };
    outputs = inputs:
        inputs.flake-parts.lib.mkFlake {inherit inputs;} {
            systems = ["x86_64-linux"];
            perSystem = {pkgs, ...}: let
                buildInputs = with pkgs; [
                    dotnet-sdk
                    curl
                    wget
                    unzip
                ];
            in {
                devShells.default = pkgs.mkShell {
                    inherit buildInputs;
                };
                packages.default = pkgs.writeShellApplication {
                    name = "cosmic-wine-fixes-builder";
                    runtimeInputs = buildInputs;
                    text = ''
                        #!/usr/bin/env bash
                        set -euo pipefail

                        # --- Argument and Path Validation ---
                        if [ -z "''${1-}" ]; then
                            echo "ERROR: You must provide the path to your Steam library directory." >&2
                            echo "Usage: $0 /path/to/your/steam/library" >&2
                            exit 1
                        fi
                        STEAM_PATH=$(realpath "$1")

                        # --- Create a temporary directory and cd into it ---
                        TMP_DIR=$(mktemp -d)
                        export TMP_DIR
                        cd "$TMP_DIR"

                        # --- Cleanup function to be called automatically on script exit ---
                        cleanup() {
                            echo "Cleaning up temporary files..."
                            rm -rf "$TMP_DIR"
                        }
                        trap cleanup EXIT

                        SE_BIN64_PATH="$STEAM_PATH/steamapps/common/SpaceEngineers/Bin64"

                        if [ ! -d "$SE_BIN64_PATH" ]; then
                            echo "ERROR: Space Engineers Bin64 directory not found at: $SE_BIN64_PATH" >&2
                            exit 1
                        fi

                        # --- Main Build Logic ---
                        echo "Copying source to temporary directory..."
                        cp -r ${inputs.self}/. .
                        chmod -R u+w .

                        # 1. Create Symlink for the build process
                        echo "1. Creating symlink for build..."
                        ln -s "$SE_BIN64_PATH" ./Bin64

                        # 2. Clean and Build the plugin. The project's `deploy.sh` handles copying the DLL.
                        echo "2. Cleaning and building plugin..."
                        dotnet clean --nologo
                        dotnet build --nologo

                        # 3. Download the launcher
                        echo "3. Downloading SpaceEngineersLauncher..."
                        LAUNCHER_URL=$(curl -s https://api.github.com/repos/sepluginloader/SpaceEngineersLauncher/releases/latest | grep "browser_download_url.*\.exe" | cut -d '"' -f 4 | head -n 1)
                        if [ -z "$LAUNCHER_URL" ]; then
                            echo "ERROR: Could not find launcher download URL from GitHub API." >&2
                            exit 1
                        fi
                        wget -q "$LAUNCHER_URL" -O SpaceEngineersLauncher.exe

                        # 4. Download NLog.dll
                        echo "4. Downloading NLog.dll..."
                        wget -q https://www.nuget.org/api/v2/package/NLog/4.7.15 -O nlog.nupkg
                        mkdir -p nlog_temp
                        unzip -q nlog.nupkg -d nlog_temp

                        # 5. Place launcher and NLog.dll in the game's Bin64 directory
                        echo "5. Placing NLog.dll and launcher in $SE_BIN64_PATH..."
                        mv ./SpaceEngineersLauncher.exe "$SE_BIN64_PATH/"
                        mv ./nlog_temp/lib/net45/NLog.dll "$SE_BIN64_PATH/"

                        echo ""
                        echo "✅ Done!"
                        echo "Plugin has been built and deployed to $SE_BIN64_PATH/Plugins/Local"
                        echo "NLog.dll and SpaceEngineersLauncher.exe have been placed in $SE_BIN64_PATH"
                    '';
                };
            };
        };
}
