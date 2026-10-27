import {
  BlockscoutStyleSourceCode,
  diffCode,
  getSourceCode,
  parseBlockscoutStyleSourceCode,
  parseEtherscanStyleSourceCode,
  StandardJsonInput,
} from "@aave-dao/toolbox";
import {
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "fs";
import path from "path";
import { Hex, getAddress, slice } from "viem";

function bytes32ToAddress(bytes32: Hex) {
  return getAddress(slice(bytes32, 12, 32));
}

// Set the target directory
const directoryPath = path.join(__dirname, "reports");
const erc1967ImplSlot =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

// diff all the networks
const files = readdirSync(directoryPath);

// Filter files ending with '_after'
const filteredFiles = files.filter((file) => file.endsWith("_after.json"));

async function diff({
  address1,
  address2,
  chainId1,
  chainId2,
  flatten,
  output,
  path = "./diffs/code",
}) {
  const sources = await Promise.all([
    getSourceCode({
      chainId: Number(chainId1),
      address: address1 as any,
      apiKey: process.env.ETHERSCAN_API_KEY,
      apiUrl: process.env.EXPLORER_PROXY,
    }),
    getSourceCode({
      chainId: Number(chainId2),
      address: address2 as any,
      apiKey: process.env.ETHERSCAN_API_KEY,
      apiUrl: process.env.EXPLORER_PROXY,
    }),
  ]);
  const source1: StandardJsonInput = (sources[0] as BlockscoutStyleSourceCode)
    .AdditionalSources
    ? parseBlockscoutStyleSourceCode(sources[0] as BlockscoutStyleSourceCode)
    : parseEtherscanStyleSourceCode(sources[0].SourceCode);
  const source2: StandardJsonInput = (sources[1] as BlockscoutStyleSourceCode)
    .AdditionalSources
    ? parseBlockscoutStyleSourceCode(sources[1] as BlockscoutStyleSourceCode)
    : parseEtherscanStyleSourceCode(sources[1].SourceCode);
  const diff = await diffCode(source1, source2);
  if (flatten || output === "stdout") {
    const flat = Object.keys(diff).reduce((acc, key) => {
      acc += diff[key];
      return acc;
    }, "");
    if (output === "stdout") {
      console.log(flat);
    } else {
      const filePath = `${path}/${chainId1}`;
      mkdirSync(filePath, { recursive: true });
      writeFileSync(`${filePath}/${address1}_${address2}.patch`, flat);
    }
  } else {
    const filePath = `${path}/${chainId1}/${address1}_${address2}`;
    mkdirSync(filePath, { recursive: true });
    Object.keys(diff).map((file) => {
      writeFileSync(`${filePath}/${file}.patch`, diff[file]);
    });
  }
}

for (const file of filteredFiles) {
  const contentBefore = JSON.parse(
    readFileSync(`${directoryPath}/${file.replace("_after", "_before")}`, {
      encoding: "utf8",
    }),
  );
  const contentAfter = JSON.parse(
    readFileSync(`${directoryPath}/${file}`, { encoding: "utf8" }),
  );
  console.log("starting ", contentBefore.chainId);

  // diff slots that are not pure implementation slots (e.g. things on addresses provider)
  await diff({
    address1: contentBefore.poolConfig.protocolDataProvider,
    chainId1: contentBefore.chainId,
    address2: contentAfter.poolConfig.protocolDataProvider,
    chainId2: contentAfter.chainId,
    output: "file",
  });

  for (const contract in contentAfter.raw) {
    const implSlot = contentAfter.raw[contract].stateDiff[erc1967ImplSlot];
    if (implSlot) {
      await diff({
        address1: bytes32ToAddress(implSlot.previousValue),
        chainId1: contentBefore.chainId,
        address2: bytes32ToAddress(implSlot.newValue),
        chainId2: contentAfter.chainId,
        output: "file",
      });
    }
  }
}

// now as the diffing is done, let's remove duplicates and generate a report
// Function to read files recursively
function getFiles(
  dir,
  fileList: { path: string; name: string; content: string }[] = [],
) {
  const files = readdirSync(dir);

  files.forEach((file) => {
    const filePath = path.join(dir, file);
    if (statSync(filePath).isDirectory()) {
      getFiles(filePath, fileList);
    } else {
      fileList.push({
        path: filePath,
        name: file,
        content: readFileSync(filePath, { encoding: "utf8" }),
      });
    }
  });

  return fileList;
}

// Get all files including subdirectories
// Normalize patch content by trimming paths in --- / +++ lines to just the filename
function normalizePatch(content: string): string {
  return content
    .split("\n")
    .map((line) => {
      if (line.startsWith("--- ") || line.startsWith("+++ ")) {
        const prefix = line.slice(0, 4);
        const filePath = line.slice(4);
        return prefix + filePath.split("/").pop();
      }
      return line;
    })
    .join("\n")
    .trim();
}

const allFiles = getFiles(path.join(__dirname, "diffs", "code"));
const uniqueArray = allFiles
  .sort((a, b) => {
    const extractNumber = (str) => {
      const match = str.match(/\/diffs\/code\/(\d+)\//);
      return match ? parseInt(match[1], 10) : Infinity;
    };

    return extractNumber(a.path) - extractNumber(b.path);
  })
  .filter(
    (obj, index, self) =>
      index === self.findIndex((o) => normalizePatch(o.content) === normalizePatch(obj.content)),
  );

for (const file of allFiles) {
  const isUnique = uniqueArray.find((uniq) => uniq.path === file.path);
  if (!isUnique) unlinkSync(file.path);
}
