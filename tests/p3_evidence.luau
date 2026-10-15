--!strict
-- Emits P3 evidence JSON: seed replay digests and the per-tick phase order.
local World = require("../src/server/Simulation/World")

local function run(): ({ string }, number)
	local world = World.new({ stageId = "s03" })
	world.resources.foodMilli = 40000
	World.spawnEnemy(world, "brute", 60)
	World.spawnEnemy(world, "spitter", 70)
	World.spawnEnemy(world, "scrapper", 80)
	local digests: { string } = {}
	for index = 1, 600 do
		local commands: { any } = {}
		if index % 20 == 0 then
			table.insert(commands, {
				kind = "Summon",
				slot = (index // 20) % 3 + 1,
				requestId = "e" .. index,
				commandSeq = index,
			})
		end
		World.step(world, { commands = commands, axis = if index % 60 < 30 then 1 else -1 })
		if index % 100 == 0 then
			table.insert(digests, World.digest(world))
		end
	end
	return digests, #world.order
end

local first, entitiesA = run()
local second, entitiesB = run()
local same = #first == #second and entitiesA == entitiesB
for index, value in first do
	same = same and value == second[index]
end
local traced = World.new({ stageId = "s01", trace = true })
World.step(traced)
World.step(traced)
print(
	string.format(
		'{"seedReplay":{"ticks":600,"checkpoints":["%s"],"replayCheckpoints":["%s"],"identical":%s},'
			.. '"tickOrder":{"declared":["%s"],"observedTwoTicks":["%s"]}}',
		table.concat(first, '","'),
		table.concat(second, '","'),
		tostring(same),
		table.concat(World.PHASES, '","'),
		table.concat(traced.trace :: { string }, '","')
	)
)
