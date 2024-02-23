{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rk3588-implicit-sync = {
      url = "gitlab:panfork/rk3588-implicit-sync";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }:
    let
      # Overlay to allow missing modules
      allowMissingModulesOverlay = final: super: {
        makeModulesClosure = x:
          builtins.trace "Applying allowMissingModulesOverlay" (super.makeModulesClosure (x // { allowMissing = true; }));
      };

      # Overlay for customizing linuxManualConfig
      linuxManualConfigOverlay = final: super: {
        linuxManualConfig = super.linuxManualConfig.override {
          stdenv = super.gcc10Stdenv;
          buildPackages = super.buildPackages // {
            stdenv = super.buildPackages.gcc10Stdenv;
          };
        };
      };

      # Import nixpkgs with both overlays
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        crossSystem.config = "aarch64-unknown-linux-gnu";
        overlays = [ linuxManualConfigOverlay ];
      };

      linux_armbian = (pkgs.linuxManualConfig {
        version = "5.10.160";
        src = pkgs.fetchzip {
          url = "https://github.com/armbian/linux-rockchip/archive/99a6d693684e987cd843d6e9bf71ebcb55de51f0.zip";
          hash = "sha256-Ncw+x84AwScG/aZtMndmDueBEopHtqO4+oqYgfWNd7U=";
        };
        configfile = ./config_armbian;
        kernelPatches = [
        ];
        allowImportFromDerivation = true;
      })
      .overrideAttrs (old: {
        name = "k";
        nativeBuildInputs = old.nativeBuildInputs ++ (with pkgs.buildPackages; [
          ubootTools
        ]);
#        prePatch = ''
#          rm arch/arm64/boot/dts/rockchip/*.dts* !("rk3588s-khadas-edge2.dts"|"rk3588s.dtsi"|"rk3588s-khadas-edge2.dtsi"|"rk3588-rk806-single-khadas.dtsi"|"rk3588-linux.dtsi"|"rk3588s-khadas-edge2-camera.dtsi")
 #       '';
      });

      linux_khadas = (pkgs.linuxManualConfig {
        version = "5.10.66";
        src = pkgs.fetchzip {
          url = "https://github.com/khadas/linux/archive/refs/tags/khadas-edges-linux-5.10-v1.5-release.tar.gz";
          hash = "sha256-7SDRxUHsM8xM4Dgtd6VxBQYpnVKCe7RH9BB1JDVWx7U=";
        };
        configfile = ./config_khadas;
        kernelPatches = [
          { name = "bcmdhd-sourcetree-fix"; patch = ./patches/bcmdhd-sourcetree-fix.patch; }
        ];
        allowImportFromDerivation = true;
      })
      .overrideAttrs (old: {
        name = "k";
        nativeBuildInputs = old.nativeBuildInputs ++ (with pkgs.buildPackages; [
          ubootTools
        ]);
      });

      generateISO = kernelPackage: let
        aarch64Pkgs = import nixpkgs {
          system = "aarch64-linux";
          overlays = [ allowMissingModulesOverlay ];
        };
      in
        nixos-generators.nixosGenerate {
          system = "aarch64-linux";
          pkgs = aarch64Pkgs;
          format = "install-iso";
          modules = [
            ({ pkgs, ... }: {
              boot.kernelPackages = pkgs.linuxPackagesFor kernelPackage;
              services.openssh.enable = true;
              # Include other desired NixOS configuration options here
            })
          ];
        };

      iso_khadas = generateISO linux_khadas;
      iso_armbian = generateISO linux_armbian;

    in {

      packages.aarch64-linux = {
        iso_khadas = iso_khadas;
        iso_armbian = iso_armbian;
      };

      packages.x86_64-linux = {
        linux_khadas = linux_khadas;
        linux_armbian = linux_armbian;
      };

      devShells.x86_64-linux.default = linux_khadas.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ (with pkgs; [ ncurses pkg-config ]);
        shellHook = ''
          addToSearchPath PKG_CONFIG_PATH ${pkgs.buildPackages.ncurses.dev}/lib/pkgconfig
        '';
        });

    };
}
