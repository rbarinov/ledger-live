// @flow

import lzw from "node-lzw";
import type { AccountData } from "./types";
import * as qrstreamImporter from "../qrstream/importer";

export type Result = {
  accounts: AccountData[],
  meta: {
    exporterName: string,
    exporterVersion: string
  }
};

export const parseChunksReducer = qrstreamImporter.parseChunksReducer;

export const areChunksComplete = qrstreamImporter.areChunksComplete;

export function chunksToResult(rawChunks: *): Result {
  const result = qrstreamImporter.chunksToResult(rawChunks);
  return JSON.parse(lzw.decode(result));
}
