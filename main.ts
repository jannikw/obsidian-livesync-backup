import * as path from "jsr:@std/path";
import { walk } from "@std/fs/walk";
import {
  DirectFileManipulator,
  type DirectFileManipulatorOptions,
} from "./lib/src/API/DirectFileManipulatorV2.ts";
import { decodeBinary } from "./lib/src/string_and_binary/convert.ts";
import { DEFAULT_SETTINGS } from "./lib/src/common/types.ts";

function loadConfigFromEnv(): DirectFileManipulatorOptions {
  function getEnv(key: string): string {
    const value = Deno.env.get(key);
    if (value === undefined) {
      throw new Error(`Environment variable ${key} is not set`);
    }
    return value;
  }

  const cfg = {
    "database": getEnv("LIVESYNC_COUCHDB_DATABASE"),
    "username": getEnv("LIVESYNC_COUCHDB_USERNAME"),
    "password": getEnv("LIVESYNC_COUCHDB_PASSWORD"),
    "url": getEnv("LIVESYNC_COUCHDB_URL"),
    "passphrase": getEnv("LIVESYNC_PASSPHRASE"),
    "obfuscatePassphrase": getEnv("LIVESYNC_PASSPHRASE"),

    // Use defaults for the rest of the settings
    useEden: DEFAULT_SETTINGS.useEden,
    maxChunksInEden: DEFAULT_SETTINGS.maxChunksInEden,
    maxTotalLengthInEden: DEFAULT_SETTINGS.maxTotalLengthInEden,
    maxAgeInEden: DEFAULT_SETTINGS.maxAgeInEden,
    enableCompression: DEFAULT_SETTINGS.enableCompression,
    enableChunkSplitterV2: DEFAULT_SETTINGS.enableChunkSplitterV2,
  } satisfies DirectFileManipulatorOptions;

  return cfg;
}

async function backup(livesync: DirectFileManipulator, backupDir: string) {
  const backupPaths = new Set<string>();

  for await (const doc of livesync.enumerateAllNormalDocs({ metaOnly: true })) {
    // console.log("ENUM", doc);

    if (doc.deleted) {
      continue;
    }

    // Create parent directories if needed
    const dir = path.dirname(doc.path);
    await Deno.mkdir(path.join(backupDir, dir), { recursive: true });

    const filePath = path.join(backupDir, doc.path);
    backupPaths.add(filePath);

    // Compare file modification time and size with the one in doc
    // FIXME: This would be more robust if we used a hash of the file content,
    //        but the meta data does not contain a hash.
    const stat = await Deno.stat(filePath).catch(() => null);
    const mtime = new Date(doc.mtime);
    if (
      stat && stat.mtime?.getTime() === mtime.getTime() &&
      stat.size === doc.size
    ) {
      console.error("SKIP", doc.path);
      continue;
    }

    console.error("BACKUP", doc.path);

    // Open file at doc.path for writing, creating parent directiories if needed
    using file = await Deno.open(filePath, {
      write: true,
      create: true,
      truncate: true,
    });
    const writer = file.writable.getWriter();
    // Set file modification time to doc.mtime

    const content = await livesync.getByMeta(doc);
    // Write binary or plain text content to the file
    if (content.type === "newnote") {
      const data = new Uint8Array(decodeBinary(content.data));
      await writer.write(data);
    } else if (content.type === "plain") {
      const encoder = new TextEncoder();
      for (const line of content.data) {
        await writer.write(encoder.encode(line));
      }
    } else {
      throw new Error(`Unsupported content type: ${content.type}`);
    }

    await Deno.utime(filePath, mtime, mtime);
  }

  // Remove files that are not in the backup list (recursive)
  for await (const entry of walk(backupDir)) {
    if (entry.isFile && !backupPaths.has(entry.path)) {
      console.error("REMOVE", entry.path);
      await Deno.remove(entry.path);
    }
  }
}

async function main() {
  if (Deno.args.length !== 1) {
    console.error(`Usage: ${path.basename(Deno.execPath())} <backup-dir>`);
    Deno.exit(1);
  }
  const backupDir = Deno.args[0];
  const conf = loadConfigFromEnv();
  console.error(`Connecting to ${conf.url} with databse ${conf.database}...`);
  const livesync = new DirectFileManipulator(conf);

  await backup(livesync, backupDir);
  console.error("Backup completed successfully.");
}

main();
