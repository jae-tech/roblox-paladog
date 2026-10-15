--!strict
export type Definition = { presentationId: string, label: string, shape: string, height: number }
local definitions: { [string]: Definition } = {
	environment = {
		presentationId = "environment_placeholder",
		label = "원정 지면",
		shape = "Ground",
		height = 0.25,
	},
	wayfinder = {
		presentationId = "wayfinder_placeholder",
		label = "등불 탐사자",
		shape = "Lantern",
		height = 3.8,
	},
	vanguard = {
		presentationId = "vanguard_placeholder",
		label = "선봉 기계",
		shape = "Block",
		height = 2.4,
	},
	slinger = {
		presentationId = "slinger_placeholder",
		label = "투척 기계",
		shape = "Ball",
		height = 2.8,
	},
	bulwark = {
		presentationId = "bulwark_placeholder",
		label = "방벽 기계",
		shape = "Shield",
		height = 3.5,
	},
	scrapper = {
		presentationId = "scrapper_placeholder",
		label = "고철병",
		shape = "Wedge",
		height = 2.4,
	},
	spitter = {
		presentationId = "spitter_placeholder",
		label = "분사기",
		shape = "Ball",
		height = 2.8,
	},
	brute = {
		presentationId = "brute_placeholder",
		label = "고철 거구",
		shape = "Shield",
		height = 4.2,
	},
	core = { presentationId = "core_placeholder", label = "신호 핵", shape = "Core", height = 6 },
	ally_bolt = {
		presentationId = "ally_bolt_placeholder",
		label = "아군 탄",
		shape = "Bolt",
		height = 0.35,
	},
	enemy_bolt = {
		presentationId = "enemy_bolt_placeholder",
		label = "적군 탄",
		shape = "Bolt",
		height = 0.35,
	},
	pulse = {
		presentationId = "pulse_placeholder",
		label = "등불 파동",
		shape = "Ball",
		height = 0.6,
	},
}
for _, def in definitions do
	table.freeze(def)
end
table.freeze(definitions)
local function resolve(definitionId: string, kind: string?): Definition
	local alias = if definitionId == "pulse_bolt"
		then "pulse"
		elseif definitionId == "enemy_core" then "core"
		else definitionId
	return definitions[alias]
		or (if kind == "Objective" then definitions.core else definitions.vanguard)
end
local function chooseRenderer(requested: string?, available: { [string]: boolean }): string
	if requested and available[requested] then
		return requested
	end
	return "Placeholder"
end
local function jitter(entityId: number): number
	return ((entityId * 17) % 11 - 5) * 0.08
end
return table.freeze({
	resolve = resolve,
	chooseRenderer = chooseRenderer,
	jitter = jitter,
	definitions = definitions,
})
