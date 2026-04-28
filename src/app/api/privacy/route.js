import { NextResponse } from "next/server";
import {
  getPrivacySettings,
  updatePrivacySettings
} from "@/lib/privacyDb";

export async function GET() {
  try {
    const settings = await getPrivacySettings();
    return NextResponse.json({ settings });
  } catch (error) {
    console.error("Error getting privacy settings:", error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function PATCH(request) {
  try {
    const body = await request.json();
    const settings = await updatePrivacySettings(body);
    return NextResponse.json(settings);
  } catch (error) {
    console.error("Error updating privacy settings:", error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
