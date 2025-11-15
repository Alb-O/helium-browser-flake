Flake for [imput's Helium browser](https://helium.computer/)

The source is kept up to date via a Github Action.

There are four outputs:
- `helium` - Latest stable release
- `helium-appimage` - Latest stable release (AppImage)
- `helium-prerelease` - Latest pre-release
- `helium-prerelease-appimage` - Latest pre-release (AppImage)

You should most likely pick the `helium` version for stable releases.
The AppImage versions exist primarily for compatibility reasons.

```nix
helium-browser = {
  url = "github:ominit/helium-browser-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```nix
# Stable release
inputs.helium-browser.packages."${pkgs.system}".helium

# Pre-release
inputs.helium-browser.packages."${pkgs.system}".helium-prerelease
```
