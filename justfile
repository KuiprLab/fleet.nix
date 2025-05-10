alias d := deploy
alias u := update

default:
    just --list


deploy:
    @git pull
    @nixos-rebuild switch --flake .


update:
    @git pull
    nix --extra-experimental-features flakes --extra-experimental-features nix-command flake update
