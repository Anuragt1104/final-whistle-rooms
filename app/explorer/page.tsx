import type { Metadata } from "next";
import ExplorerClient from "./ExplorerClient";

export const metadata: Metadata = {
  title: "TxODDS Feed Explorer — every message, every field",
  description:
    "Interactive documentation and live visualization of the TxODDS soccer scores feed: all message types, fields and real responses.",
};

export default function ExplorerPage() {
  return <ExplorerClient />;
}
