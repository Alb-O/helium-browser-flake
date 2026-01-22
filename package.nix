{...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    sources = builtins.fromJSON (builtins.readFile ./sources.json);
    stableInfo = sources.stable.${system};
    prereleaseInfo = sources.prerelease.${system};

    pname = "helium";

    mkDesktopItem = pkgs.makeDesktopItem {
      name = pname;
      desktopName = "Helium";
      genericName = "Web Browser";
      comment = "Access the Internet";
      exec = "${pname} %U";
      icon = pname;
      terminal = false;
      categories = ["Network" "WebBrowser"];
      mimeTypes = [
        "text/html"
        "text/xml"
        "application/xhtml+xml"
        "application/vnd.mozilla.xul+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/about"
        "x-scheme-handler/unknown"
      ];
      startupNotify = true;
      startupWMClass = "helium";
    };

    mkHeliumAppImage = info:
      pkgs.appimageTools.wrapType2 {
        version = info.version;
        pname = "${pname}-appimage";
        src = pkgs.fetchurl {
          url = info.appimage_url;
          hash = info.appimage_sha256;
        };

        nativeBuildInputs = [pkgs.copyDesktopItems];
        desktopItems = [mkDesktopItem];
      };

    mkHelium = info:
      pkgs.stdenv.mkDerivation {
        inherit pname;
        version = info.version;
        src = pkgs.fetchurl {
          url = info.tar_url;
          hash = info.tar_sha256;
        };

        nativeBuildInputs = with pkgs; [
          autoPatchelfHook
          patchelfUnstable
          copyDesktopItems
          kdePackages.wrapQtAppsHook
          makeWrapper
        ];

        buildInputs = with pkgs; [
          libgbm
          glibc
          glib
          dbus
          expat
          cups
          nspr
          nss
          libx11
          libxcb
          libxext
          libxfixes
          libxrandr
          cairo
          pango
          at-spi2-atk
          atk
          gtk3
          alsa-lib
          at-spi2-core
          qt6.qtbase
          qt6.qtwayland
          vulkan-loader
          libva
          libvdpau
          libglvnd
          mesa
          glib
          fontconfig
          freetype
          pango
          cairo
          libx11
          atk
          nss
          nspr
          libxcursor
          libxext
          libxfixes
          libxrender
          libxcb
          alsa-lib
          expat
          cups
          dbus
          gdk-pixbuf
          gcc-unwrapped.lib
          systemd
          libexif
          pciutils
          liberation_ttf
          curl
          util-linux
          wget
          flac
          harfbuzz
          icu
          libpng
          snappy
          speechd
          bzip2
          libcap
          at-spi2-atk
          at-spi2-core
          libkrb5
          libdrm
          libglvnd
          libgbm
          coreutils
          libxkbcommon
          pipewire
          wayland
        ];

        runtimeDependencies = with pkgs; [libGL];

        appendRunpaths = [
          "${pkgs.libGL}/lib"
          "${pkgs.mesa}/lib"
          "${pkgs.vulkan-loader}/lib"
          "${pkgs.libva}/lib"
          "${pkgs.libvdpau}/lib"
        ];

        patchelfFlags = ["--no-clobber-old-sections"];
        autoPatchelfIgnoreMissingDeps = ["libQt5Core.so.5" "libQt5Gui.so.5" "libQt5Widgets.so.5"];

        installPhase = ''
          runHook preInstall

          libExecPath="$prefix/lib/${pname}-bin-$version"
          mkdir -p "$libExecPath"
          cp -rv ./ "$libExecPath/"

          makeWrapper "$libExecPath/helium-wrapper" "$out/bin/${pname}" \
            --prefix LD_LIBRARY_PATH : "$rpath" \
            --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
            --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtwayland}/${pkgs.qt6.qtbase.qtPluginPrefix}"

          # Install desktop file
          mkdir -p "$out/share/applications"
          cp "${mkDesktopItem}/share/applications/"*.desktop "$out/share/applications/"

          # Install icon from product_logo
          for size in 16 24 32 48 64 128 256; do
            if [ -f "$libExecPath/product_logo_$size.png" ]; then
              mkdir -p "$out/share/icons/hicolor/''${size}x''${size}/apps"
              cp "$libExecPath/product_logo_$size.png" "$out/share/icons/hicolor/''${size}x''${size}/apps/${pname}.png"
            fi
          done

          runHook postInstall
        '';
      };

    # Create stable and prerelease packages
    helium = mkHelium stableInfo;
    helium-appimage = mkHeliumAppImage stableInfo;
    helium-prerelease = mkHelium prereleaseInfo;
    helium-prerelease-appimage = mkHeliumAppImage prereleaseInfo;
  in {
    packages = {
      inherit helium helium-appimage helium-prerelease helium-prerelease-appimage;

      default = helium;
    };
  };
}
