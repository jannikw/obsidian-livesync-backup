{ obsidian-livesync-backup }:
{
  pkgs,
  config,
  lib,
  ...
}:
let
  defaultPath = name: "/var/lib/obsidian-livesync-backup/${name}";
in
{
  options.services.obsidian-livesync-backup =
    let
      backupOptions = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "Enable SystemD service for backup";

          couchdbDatabaseFile = lib.mkOption {
            type = lib.types.path;
            description = "Path to a file containing the CouchDB database name.";
          };

          couchdbUsernameFile = lib.mkOption {
            type = lib.types.path;
            description = "Path to a file containing the CouchDB username.";
          };

          couchdbPasswordFile = lib.mkOption {
            type = lib.types.path;
            description = "Path to a file containing the CouchDB password.";
          };

          couchdbUrlFile = lib.mkOption {
            type = lib.types.path;
            description = "Path to a file containing the CouchDB URL.";
          };

          livesyncPassphraseFile = lib.mkOption {
            type = lib.types.path;
            description = "Passphrase for E2E encryption of Livesync";
          };

          backupPath = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to the directory where backups will be stored.";
          };
        };
      };
    in
    lib.mkOption {
      type = lib.types.attrsOf backupOptions;
      default = { };
      description = "Named entries for Obsidian Livesync Backup configuration.";
    };

  # Create default backup directories
  config.systemd.tmpfiles.rules = lib.pipe config.services.obsidian-livesync-backup [
    lib.attrsToList
    (builtins.filter ({ name, value }: value.enable && value.backupPath == null))
    (builtins.map ({ name, value }: "d ${defaultPath name} 0770 livesync-backup livesync-backup - - -"))
  ];

  # Create backup user and group
  config.users.users.livesync-backup = {
    description = "Obsidian Livesync Backup user";
    group = "livesync-backup";
    isSystemUser = true;
  };
  config.users.groups.livesync-backup = { };

  config.systemd.services = lib.pipe config.services.obsidian-livesync-backup [
    lib.attrsToList
    (builtins.filter ({ name, value }: value.enable))
    (builtins.map (
      { name, value }:
      let
        script = pkgs.writeShellApplication {
          name = "obsidian-livesync-backup-${name}";
          text = ''
            # Re-export the environment variables from the secrets files
            LIVESYNC_COUCHDB_DATABASE="$(cat "$LIVESYNC_COUCHDB_DATABASE")"
            export LIVESYNC_COUCHDB_DATABASE

            LIVESYNC_COUCHDB_USERNAME="$(cat "$LIVESYNC_COUCHDB_USERNAME")"
            export LIVESYNC_COUCHDB_USERNAME

            LIVESYNC_COUCHDB_PASSWORD="$(cat "$LIVESYNC_COUCHDB_PASSWORD")"
            export LIVESYNC_COUCHDB_PASSWORD

            LIVESYNC_COUCHDB_URL="$(cat "$LIVESYNC_COUCHDB_URL")"
            export LIVESYNC_COUCHDB_URL

            LIVESYNC_PASSPHRASE="$(cat "$LIVESYNC_PASSPHRASE")"
            export LIVESYNC_PASSPHRASE

            # Run the livesync backup command
            ${obsidian-livesync-backup}/bin/livesync-backup ${
              if value.backupPath != null then value.backupPath else defaultPath name
            }
          '';
        };
      in
      {
        name = "obsidian-livesync-backup-${name}";
        value = {
          description = "Obsidian Livesync Backup for ${name}";
          # wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${script}/bin/obsidian-livesync-backup-${name}";

            User = "livesync-backup";
            Group = "livesync-backup";

            # Provides secrets via enviuronment variables
            LoadCredential = [
              "couchdbDatabase:${value.couchdbDatabaseFile}"
              "couchdbUsername:${value.couchdbUsernameFile}"
              "couchdbPassword:${value.couchdbPasswordFile}"
              "couchdbUrl:${value.couchdbUrlFile}"
              "livesyncPassphrase:${value.livesyncPassphraseFile}"
            ];
            Environment = [
              "LIVESYNC_COUCHDB_DATABASE=%d/couchdbDatabase"
              "LIVESYNC_COUCHDB_USERNAME=%d/couchdbUsername"
              "LIVESYNC_COUCHDB_PASSWORD=%d/couchdbPassword"
              "LIVESYNC_COUCHDB_URL=%d/couchdbUrl"
              "LIVESYNC_PASSPHRASE=%d/livesyncPassphrase"
            ];
          };
        };
      }
    ))
    lib.traceValSeq
    builtins.listToAttrs
  ];
}
