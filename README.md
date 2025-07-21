# Livesync Backup

A small Deno application to create a snapshot of the current Obsidian notes managed by Obsidian LiveSync. The tool is meant to be integrated into a automated backup process, where the tool first pulls all notes into a local directory. Next, you can automate Git to create a commit or use a tool like Restic to backup the data.

The application uses the Obsidian LiveSync commonlib to communicate with CouchDB and enumerates all available documents.

## Developement

nix build '.?submodules=1#default' --print-build-logs