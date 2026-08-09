import { createHash } from "node:crypto";
import { deflateRawSync, gunzipSync, gzipSync, inflateRawSync } from "node:zlib";
import fs from "node:fs/promises";
import path from "node:path";

export const FIXED_MTIME = 1_767_225_600;

export async function sha256(file) {
  return createHash("sha256").update(await fs.readFile(file)).digest("hex");
}

export async function filesUnder(root) {
  const files = [];
  async function visit(directory) {
    for (const entry of (await fs.readdir(directory, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) await visit(target);
      else if (entry.isFile()) files.push(target);
      else throw new Error(`unsupported archive source entry: ${target}`);
    }
  }
  await visit(root);
  return files;
}

export async function writeTarGz(root, output, stem) {
  const chunks = [];
  for (const file of await filesUnder(root)) {
    const relative = `${stem}/${path.relative(root, file).split(path.sep).join("/")}`;
    const data = await fs.readFile(file);
    chunks.push(tarHeader(relative, data.length, relative.endsWith("/caudex") || relative.endsWith("/caudex.exe") ? 0o755 : 0o644));
    chunks.push(data);
    chunks.push(Buffer.alloc((512 - (data.length % 512)) % 512));
  }
  chunks.push(Buffer.alloc(1024));
  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(output, gzipSync(Buffer.concat(chunks), { mtime: 0 }));
}

export async function writeZip(root, output, stem) {
  const local = [];
  const central = [];
  const date = dosDate(new Date("2026-01-01T00:00:00Z"));
  const time = dosTime(new Date("2026-01-01T00:00:00Z"));
  let offset = 0;
  for (const file of await filesUnder(root)) {
    const relative = `${stem}/${path.relative(root, file).split(path.sep).join("/")}`;
    const name = Buffer.from(relative);
    const data = await fs.readFile(file);
    const crc = crc32(data);
    const compressed = deflateRawSync(data, { level: 9 });
    const method = compressed.length < data.length ? 8 : 0;
    const body = method === 8 ? compressed : data;
    const header = Buffer.alloc(30 + name.length);
    header.writeUInt32LE(0x04034b50, 0);
    header.writeUInt16LE(20, 4);
    header.writeUInt16LE(0, 6);
    header.writeUInt16LE(method, 8);
    header.writeUInt16LE(time, 10);
    header.writeUInt16LE(date, 12);
    header.writeUInt32LE(crc, 14);
    header.writeUInt32LE(body.length, 18);
    header.writeUInt32LE(data.length, 22);
    header.writeUInt16LE(name.length, 26);
    name.copy(header, 30);
    local.push(header, body);

    const record = Buffer.alloc(46 + name.length);
    record.writeUInt32LE(0x02014b50, 0);
    record.writeUInt16LE(20, 4);
    record.writeUInt16LE(20, 6);
    record.writeUInt16LE(0, 8);
    record.writeUInt16LE(method, 10);
    record.writeUInt16LE(time, 12);
    record.writeUInt16LE(date, 14);
    record.writeUInt32LE(crc, 16);
    record.writeUInt32LE(body.length, 20);
    record.writeUInt32LE(data.length, 24);
    record.writeUInt16LE(name.length, 28);
    record.writeUInt16LE(0, 30);
    record.writeUInt16LE(0, 32);
    record.writeUInt16LE(0, 34);
    record.writeUInt16LE(0, 36);
    record.writeUInt32LE(relative.endsWith("/caudex.exe") ? 0x81ed0000 : 0x81a40000, 38);
    record.writeUInt32LE(offset, 42);
    name.copy(record, 46);
    central.push(record);
    offset += header.length + body.length;
  }
  const centralData = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(central.length, 8);
  end.writeUInt16LE(central.length, 10);
  end.writeUInt32LE(centralData.length, 12);
  end.writeUInt32LE(offset, 16);
  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(output, Buffer.concat([...local, centralData, end]));
}

export async function archiveEntries(file) {
  const data = await fs.readFile(file);
  return file.endsWith(".zip") ? zipEntries(data) : tarEntries(gunzipSync(data));
}

export async function readArchiveEntry(file, wanted) {
  const data = await fs.readFile(file);
  return file.endsWith(".zip")
    ? readZipEntry(data, wanted)
    : readTarEntry(gunzipSync(data), wanted);
}

function tarHeader(name, size, mode) {
  const header = Buffer.alloc(512);
  writeString(header, 0, 100, name);
  writeOctal(header, 100, 8, mode);
  writeOctal(header, 108, 8, 0);
  writeOctal(header, 116, 8, 0);
  writeOctal(header, 124, 12, size);
  writeOctal(header, 136, 12, FIXED_MTIME);
  header.fill(0x20, 148, 156);
  header[156] = 0x30;
  writeString(header, 257, 6, "ustar\0");
  writeString(header, 263, 2, "00");
  writeString(header, 265, 32, "root");
  writeString(header, 297, 32, "root");
  writeOctal(header, 148, 8, header.reduce((sum, value) => sum + value, 0));
  return header;
}

function writeString(buffer, offset, length, value) {
  Buffer.from(value).copy(buffer, offset, 0, length);
}

function writeOctal(buffer, offset, length, value) {
  const text = Math.floor(value).toString(8).padStart(length - 1, "0");
  writeString(buffer, offset, length, `${text}\0`);
}

function tarEntries(data) {
  const entries = [];
  let offset = 0;
  while (offset + 512 <= data.length && data.subarray(offset, offset + 512).some(Boolean)) {
    const header = data.subarray(offset, offset + 512);
    const name = readString(header, 0, 100);
    const size = parseInt(readString(header, 124, 12).trim() || "0", 8);
    const bodyOffset = offset + 512;
    entries.push({ name, data: data.subarray(bodyOffset, bodyOffset + size) });
    offset = bodyOffset + Math.ceil(size / 512) * 512;
  }
  return entries;
}

function readTarEntry(data, wanted) {
  const entry = tarEntries(data).find((value) => value.name === wanted);
  if (!entry) throw new Error(`archive entry not found: ${wanted}`);
  return entry.data;
}

function zipEntries(data) {
  const entries = [];
  let offset = 0;
  while (offset + 30 <= data.length && data.readUInt32LE(offset) === 0x04034b50) {
    const method = data.readUInt16LE(offset + 8);
    const compressedSize = data.readUInt32LE(offset + 18);
    const nameLength = data.readUInt16LE(offset + 26);
    const extraLength = data.readUInt16LE(offset + 28);
    const name = data.subarray(offset + 30, offset + 30 + nameLength).toString();
    const body = data.subarray(offset + 30 + nameLength + extraLength, offset + 30 + nameLength + extraLength + compressedSize);
    entries.push({ name, data: method === 8 ? inflateRawSync(body) : body });
    offset += 30 + nameLength + extraLength + compressedSize;
  }
  return entries;
}

function readZipEntry(data, wanted) {
  const entry = zipEntries(data).find((value) => value.name === wanted);
  if (!entry) throw new Error(`archive entry not found: ${wanted}`);
  return entry.data;
}

function readString(buffer, offset, length) {
  return buffer.subarray(offset, offset + length).toString().replace(/\0.*$/, "");
}

function dosDate(value) {
  return ((value.getUTCFullYear() - 1980) << 9) | ((value.getUTCMonth() + 1) << 5) | value.getUTCDate();
}

function dosTime(value) {
  return (value.getUTCHours() << 11) | (value.getUTCMinutes() << 5) | Math.floor(value.getUTCSeconds() / 2);
}

function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
