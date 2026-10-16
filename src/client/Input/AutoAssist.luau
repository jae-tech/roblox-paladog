--!strict
-- Per-button auto summon / auto weapon (D-AUTO-01). Pressing a summon or weapon button toggles that
-- slot's auto on or off; while on, the client sends the same command a press would whenever the HUD
-- readiness check passes. The server still validates every command, so rules and rewards are unchanged.
local Text = require("../Presentation/Text")

local RETRY_SECONDS = 0.5 -- per slot, so a pending or refused command is not resent every frame
local WEAPON_RANGE = 500 -- weapons fire only with a living enemy this close to the hero (x/z distance)
-- Modes whose buttons are not plain summons/weapons keep one press = one command.
local MANUAL_MODES: { [string]: boolean } = { Destiny = true, Tower = true, Jump = true }

export type Decision = { kind: string, unit: number?, slot: number? }

local AutoAssist = {}

function AutoAssist.new(catalog: any)
	local summonOn: { [number]: boolean } = {}
	local weaponOn: { [number]: boolean } = {}
	local lastTry: { [string]: number } = {}
	local self = {}

	function self.eligible(mode: string?): boolean
		return mode ~= nil and not MANUAL_MODES[mode]
	end

	-- Returns the new state of that slot.
	function self.toggle(kind: string, n: number): boolean
		local list = if kind == "Summon" then summonOn else weaponOn
		list[n] = not list[n]
		lastTry[kind .. n] = nil
		return list[n] == true
	end

	function self.state(): any
		local function on(list: { [number]: boolean }): { [number]: boolean }
			local copy = {}
			for n, value in list do
				if value then
					copy[n] = true
				end
			end
			return copy
		end
		return { summon = on(summonOn), weapon = on(weaponOn) }
	end

	function self.clear()
		table.clear(summonOn)
		table.clear(weaponOn)
		table.clear(lastTry)
	end

	local function due(key: string, now: number): boolean
		local last = lastTry[key]
		if last and now - last < RETRY_SECONDS then
			return false
		end
		lastTry[key] = now
		return true
	end

	local function enemyNear(view: any): boolean
		local hero
		for _, e in view.entities do
			if e.kind == "Hero" and e.team == 1 then
				hero = e
				break
			end
		end
		if not hero then
			return false
		end
		for _, e in view.entities do
			if e.team == 2 and (e.kind == "Enemy" or e.kind == "Boss") and e.hp > 0 then
				local dx, dz = e.x - hero.x, (e.z or 0) - (hero.z or 0)
				if dx * dx + dz * dz <= WEAPON_RANGE * WEAPON_RANGE then
					return true
				end
			end
		end
		return false
	end

	-- Commands to send this frame for a running, unpaused battle view.
	function self.decide(view: any, slot: any, now: number): { Decision }
		local out: { Decision } = {}
		if not view or not slot or view.paused or view.outcome or not self.eligible(view.mode) then
			return out
		end
		for n = 1, 9 do
			if
				summonOn[n]
				and Text.summonView(catalog, slot, view, n).ready
				and due("Summon" .. n, now)
			then
				table.insert(out, { kind = "Summon", unit = n })
			end
		end
		local heroFree = view.heroState == "Idle" or view.heroState == "Move"
		local near: boolean? = nil
		for i = 1, 3 do
			local code = slot.equip[i]
			if weaponOn[i] and heroFree and code and code ~= 0 then
				local _, num = Text.decode(code)
				local cost = tonumber(Text.weaponCost(catalog, slot, code))
				-- the gold weapon (num 11) spends gold, so it is never fired automatically
				if num ~= 11 and cost and view.mana >= cost then
					if near == nil then
						near = enemyNear(view)
					end
					if near and due("Mace" .. i, now) then
						table.insert(out, { kind = "Mace", slot = i })
						heroFree = false -- one weapon per frame; the hero is busy swinging after it
					end
				end
			end
		end
		return out
	end

	return self
end

return table.freeze(AutoAssist)
