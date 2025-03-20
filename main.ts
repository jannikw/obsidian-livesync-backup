globalThis.window = globalThis;

import * as path from "jsr:@std/path";

import { parse } from "@std/jsonc";
import { walk } from "@std/fs/walk";
import {
  DirectFileManipulator,
  type DirectFileManipulatorOptions,
} from "./lib/src/API/DirectFileManipulatorV2.ts";
import { decodeBinary } from "./lib/src/string_and_binary/convert.ts";

const testData = parse(Deno.readTextFileSync("./dat/config.json"));
// console.log(testData);

interface PeerCouchDBConf extends DirectFileManipulatorOptions {
  type: "couchdb";
  useRemoteTweaks?: true;
  group?: string;
  name: string;
  database: string;
  username: string;
  password: string;
  url: string;
  customChunkSize?: number;
  minimumChunkSize?: number;
  passphrase: string;
  obfuscatePassphrase: string;
  baseDir: string;
}

const conf: PeerCouchDBConf = testData.peers[0];

const man = new DirectFileManipulator(conf);

const backupDir = "./backup";

const backupPaths = new Set<string>();

for await (const doc of man.enumerateAllNormalDocs({ metaOnly: true })) {
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
  const stat = await Deno.stat(filePath).catch(() => null);
  const mtime = new Date(doc.mtime);
  if (stat && stat.mtime?.getTime() === mtime.getTime() && stat.size === doc.size) {
    console.log("SKIP", doc.path);
    continue;
  }

  console.log("BACKUP", doc.path);

  // Open file at doc.path for writing, creating parent directiories if needed
  using file = await Deno.open(filePath, {
    write: true,
    create: true,
    truncate: true,
  });
  const writer = file.writable.getWriter();
  // Set file modification time to doc.mtime
  
  const content = await man.getByMeta(doc);
  
  if (content.type === "newnote") {
    const data = new Uint8Array(decodeBinary(content.data)) 
    await writer.write(data);
  } else if (content.type === "plain") {
    const encoder = new TextEncoder();
    for (const line of content.data) {
      await writer.write(encoder.encode(line));
    }
  }

  await Deno.utime(filePath, mtime, mtime);

  
}

// Remove files that are not in the backup list (recursive)
for await (const entry of walk(backupDir)) {
  if (entry.isFile && !backupPaths.has(entry.path)) {
    console.log("REMOVE", entry.path);
    await Deno.remove(entry.path);
  }
}