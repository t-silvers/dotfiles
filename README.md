# dotfiles

x-platform dotfiles, chezmoi mgmt

## usage

Interact with using `task` and provided taskfiles. The following commands are supported:

1. `init`: Initialize dotfiles from source GitHub dotfiles repo (source -> local). Use when setting up a new machine.

2. `edit`: (currently not supported) Commit local dotfiles changes to source GitHub dotfiles repo (local -> source).

3. `update`: Sync local dotfiles with source GitHub dotfiles repo (source -> local).

4. `push`: Commit local dev changes to source GitHub dotfiles repo and `update` (dev -> source -> local).

## terms

Three locations:

1. local dotfiles $\equiv$ `~`

2. source [GitHub dotfiles repo] $\equiv$ `https://github.com/$GITHUB_USERNAME/dotfiles.git`

3. local dev $\equiv$ `~/Developer/projects/dotfiles`