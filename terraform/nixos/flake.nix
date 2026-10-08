{
  description = "warlock box: a NixOS EC2 instance with Claude Code, gh, git, and warlock";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Tracks warlock's main branch. `warlock-update` moves it forward.
    warlock.url = "github:Genetic-Pottery/warlock";
  };

  outputs =
    { nixpkgs, warlock, ... }:
    {
      nixosConfigurations.box = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit warlock; };
        modules = [ ./configuration.nix ];
      };
    };
}
