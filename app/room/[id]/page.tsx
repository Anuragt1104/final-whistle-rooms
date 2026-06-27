import { RoomClient } from "@/components/room/RoomClient";

export const dynamic = "force-dynamic";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <RoomClient id={id} />;
}
