import {
  BlockscoutStyleSourceCode,
  diffCode,
  getSourceCode,
  parseBlockscoutStyleSourceCode,
  parseEtherscanStyleSourceCode,
  StandardJsonInput,
} from "@aave-dao/toolbox";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "fs";
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

// the toolbox resolves Ink to Routescan, where these contracts are not verified
const explorerApis: Record<number, string> = {
  57073: "https://explorer.inkonchain.com/api",
};

async function fetchSource(chainId: number, address: string) {
  // sequential lookups with a pause stay under the explorers' per-second rate limits
  await new Promise((resolve) => setTimeout(resolve, 500));
  return getSourceCode({
    chainId,
    address: address as any,
    apiKey: process.env.ETHERSCAN_API_KEY,
    apiUrl: process.env.EXPLORER_PROXY ?? explorerApis[chainId],
  });
}

async function diff({
  address1,
  address2,
  chainId1,
  chainId2,
  flatten,
  output,
  path = "./diffs/code",
}) {
  const sources = [
    await fetchSource(Number(chainId1), address1),
    await fetchSource(Number(chainId2), address2),
  ];
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
