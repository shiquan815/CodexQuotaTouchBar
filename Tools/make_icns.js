#!/usr/bin/env node

const fs = require("fs");

const [, , outPath, ...entries] = process.argv;

if (!outPath || entries.length % 2 !== 0) {
  console.error("usage: make_icns.js OUT.icns TYPE PNG [TYPE PNG ...]");
  process.exit(2);
}

const chunks = [];
let totalSize = 8;

for (let index = 0; index < entries.length; index += 2) {
  const type = entries[index];
  const pngPath = entries[index + 1];
  if (!/^[A-Za-z0-9]{4}$/.test(type)) {
    console.error(`invalid icns type: ${type}`);
    process.exit(2);
  }
  const png = fs.readFileSync(pngPath);
  const header = Buffer.alloc(8);
  header.write(type, 0, 4, "ascii");
  header.writeUInt32BE(png.length + 8, 4);
  chunks.push(header, png);
  totalSize += png.length + 8;
}

const fileHeader = Buffer.alloc(8);
fileHeader.write("icns", 0, 4, "ascii");
fileHeader.writeUInt32BE(totalSize, 4);

fs.writeFileSync(outPath, Buffer.concat([fileHeader, ...chunks], totalSize));
