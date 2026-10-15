--!strict
-- Code-only opt-in after explicit user approval. Never enabled via a Remote or client setting.
local policy = {
	enabled = false,
	universeId = 10771015944,
	namespace = "LanternExpedition_P8_QA_v1",
	keyPrefix = "qa:u:",
}

local function allowed(
	config: { enabled: boolean, universeId: number },
	universeId: number,
	studio: boolean
): boolean
	return config.enabled
		and studio
		and universeId == config.universeId
		and universeId == 10771015944
end

return table.freeze({ config = table.freeze(policy), allowed = allowed })
