--!strict
-- Applies a tick's hit batch at once: every attacker alive at batch start lands (simultaneous trades),
-- each entity dies at most once and pays its kill reward once.
local SimTypes = require("./SimTypes")

type World = SimTypes.World

local function apply(world: World, hits: { SimTypes.Hit }): { SimTypes.Death }
	local totals: { [number]: number } = {}
	local targets: { number } = {}
	for _, hit in hits do
		if totals[hit.targetId] == nil then
			totals[hit.targetId] = 0
			table.insert(targets, hit.targetId)
		end
		totals[hit.targetId] += hit.damage
	end
	table.sort(targets)
	local deaths: { SimTypes.Death } = {}
	for _, id in targets do
		local target = world.entities[id]
		if target and target.state ~= "Dead" and target.hp > 0 then
			target.hp = math.max(0, target.hp - totals[id])
			if target.hp == 0 then
				target.state = "Dead"
				target.targetId = nil
				table.insert(deaths, {
					entityId = id,
					definitionId = target.definitionId,
					kind = target.kind,
					tick = world.tick,
				})
				if target.kind == "Enemy" then
					-- Provisional until settlement; never profile gold before commit (DATA_MODELS §5.1).
					world.pendingKillGold += target.killGold
					world.pendingKillXp += target.killXp
					world.killCounts[target.definitionId] = (
						world.killCounts[target.definitionId] or 0
					) + 1
				end
			end
		end
	end
	return deaths
end

return table.freeze({ apply = apply })
