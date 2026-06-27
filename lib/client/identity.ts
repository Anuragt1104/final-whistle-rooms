"use client";

import { useEffect, useState } from "react";
import { getOrCreateIdentity, loadIdentity, shortAddress, signMessage, type Identity } from "@/lib/solana/wallet";

const NAME_KEY = "fwr.name";
const memberKey = (roomId: string) => `fwr.member.${roomId}`;

export function getDisplayName(): string {
  if (typeof window === "undefined") return "";
  return window.localStorage.getItem(NAME_KEY) ?? "";
}
export function setDisplayName(name: string) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(NAME_KEY, name);
}
export function getMemberId(roomId: string): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(memberKey(roomId));
}
export function setMemberId(roomId: string, memberId: string) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(memberKey(roomId), memberId);
}

/**
 * "Continue with Solana": ensures an on-device identity exists and signs a
 * lightweight proof-of-identity message. Zero friction, no funds, no extension.
 */
export function useIdentity() {
  const [identity, setIdentity] = useState<Identity | null>(null);
  const [name, setName] = useState("");

  useEffect(() => {
    setIdentity(loadIdentity());
    setName(getDisplayName());
  }, []);

  function connect(displayName: string): Identity {
    const id = getOrCreateIdentity();
    // sign a domain message so this is a real Solana signature, not a stub
    signMessage(id, `final-whistle-rooms:auth:${displayName}:${id.pubkey}`);
    setIdentity(id);
    setName(displayName);
    setDisplayName(displayName);
    return id;
  }

  return {
    identity,
    name,
    short: identity ? shortAddress(identity.pubkey) : "",
    connect,
    ready: identity !== null,
  };
}
