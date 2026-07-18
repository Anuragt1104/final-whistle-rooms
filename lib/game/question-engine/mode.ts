export type QuestionEngineV2Mode = "off" | "shadow" | "on";

export function questionEngineMode(): QuestionEngineV2Mode {
  const raw = (process.env.QUESTION_ENGINE_V2 ?? "off").toLowerCase().trim();
  if (raw === "on" || raw === "shadow" || raw === "off") return raw;
  return "off";
}

export type EditorialContextMode = "off" | "official" | "official_gdelt";

export function editorialContextMode(): EditorialContextMode {
  const raw = (process.env.EDITORIAL_CONTEXT ?? "off").toLowerCase().trim();
  if (raw === "official" || raw === "official_gdelt" || raw === "off") return raw;
  return "off";
}

export type QuestionLlmMode = "off" | "configured";

export function questionLlmMode(): QuestionLlmMode {
  const raw = (process.env.QUESTION_LLM ?? "configured").toLowerCase().trim();
  if (raw === "off") return "off";
  return "configured";
}
