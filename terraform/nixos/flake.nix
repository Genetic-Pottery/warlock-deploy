{
  description = "warlock box: a NixOS EC2 instance with Claude Code, gh, git, and the warlock plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    {
      nixosConfigurations.box = nixpkgs.lib.nixosSystem {
        modules = [ ./configuration.nix ];
      };
    };
}
