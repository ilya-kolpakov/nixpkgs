# Creates a NixOS image for a given NixOS configuration

{ nixpkgs-path        # path to nixpkgs (<nixpkgs>)
, nixos-path          # path to nixos (<nixpkgs/nixos>)
, nixos-config-path   # path to desired NixOS config
, disk-size-mb        # image size in megabytes
}:
let

  # import the nixpkgs
  pkgs = import nixpkgs-path;

  # evaluate the target configuration
  config = (
    import nixos-path { configuration = import config-path; }
  ).config;

in
  import <nixpkgs/nixos/lib/make-disk-image.nix> {
    inherit pkgs lib config configFile diskSize;
    partitioned = true;
    fsType = "ext4";
    postVM = ''
      PATH=$PATH:${pkgs.stdenv.lib.makeBinPath [ pkgs.gnutar pkgs.gzip ]}
      pushd $out
      mv $diskImage disk.raw
      # Pack the image without the empty space in the image
      tar -Szcf nixos-image-${config.system.nixosLabel}-${pkgs.stdenv.system}.raw.tar.gz disk.raw
      rm $out/disk.raw
      popd
    '';
  }
