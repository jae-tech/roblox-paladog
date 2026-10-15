--!strict
local Definitions = require("./ViewDefinitions")
local Tokens = require("./Tokens")

local function part(parent: Instance, name: string, size: Vector3, color: Color3): Part
	local body = Instance.new("Part")
	body.Name, body.Size, body.Color = name, size, color
	body.Anchored = true
	body.CanCollide, body.CanTouch, body.CanQuery = false, false, false
	body.CastShadow = false
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = parent
	return body
end

-- Adapters only receive presentation data. They never receive World/server services.
local function placeholder(parent: Instance, def: any, id: number, team: string, kind: string): any
	local color = if kind == "Hero"
		then Tokens.amber
		elseif team == "Enemy" then Tokens.coral
		else Tokens.teal
	local width = if def.shape == "Shield" then 2.4 elseif def.shape == "Core" then 3 else 1.4
	local projectile = kind == "Projectile"
	local body = part(parent, "Entity_" .. id, Vector3.new(width, def.height, 1.2), color)
	if def.shape == "Ball" then
		body.Shape = Enum.PartType.Ball
	elseif def.shape == "Bolt" then
		body.Size = Vector3.new(1.3, 0.3, 0.3)
	end
	local marker: Part? = nil
	if not projectile then
		marker = part(parent, "Mark_" .. id, Vector3.new(width * 0.6, 0.2, 0.3), Tokens.background)
	end
	local label: TextLabel? = nil
	if not projectile then
		local billboard = Instance.new("BillboardGui")
		billboard.Name, billboard.Size = "Identity", UDim2.fromOffset(180, 50)
		billboard.StudsOffset = Vector3.new(0, def.height / 2 + 1.3, 0)
		billboard.AlwaysOnTop, billboard.MaxDistance = true, 100
		billboard.Parent = body
		local text = Instance.new("TextLabel")
		text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 0.15
		text.BackgroundColor3, text.TextColor3 = Tokens.background, color
		text.TextSize, text.Font = 12, Enum.Font.GothamMedium
		text.Parent = billboard
		label = text
	end
	local function update(snapshot: any, _alpha: number)
		local x = snapshot.x or 0
		local z = if projectile then 0 else Definitions.jitter(id)
		local y = if projectile then 2.2 else def.height / 2
		local facing = snapshot.facing or snapshot.direction or 1
		body.CFrame = CFrame.new(x, y, z)
		if marker then
			marker.CFrame = CFrame.new(x + facing * width * 0.25, y + def.height * 0.2, z + 0.65)
		end
		if label then
			local faction = if kind == "Hero"
				then "영웅"
				elseif team == "Enemy" then "적"
				else "아군"
			local support = if snapshot.inSupport then " · 지원+" else ""
			label.Text = string.format(
				"[%s] %s #%d\nHP %d/%d%s",
				faction,
				def.label,
				id,
				snapshot.hp or 0,
				snapshot.maxHp or 0,
				support
			)
		end
	end
	local function destroy()
		body:Destroy()
		if marker then
			marker:Destroy()
		end
	end
	return {
		update = update,
		play = function(
			_eventId: string,
			_state: string,
			_startTick: number,
			_durationTicks: number
		)
		end,
		destroy = destroy,
	}
end

-- Each adapter attempt owns a container. A failed factory cannot leak partially built parts.
local function new(parent: Instance, adapters: { [string]: any }?)
	local factories: { [string]: any } = { Placeholder = placeholder }
	if adapters then
		for name, adapter in adapters do
			factories[name] = adapter
		end
	end
	local records: { [number]: any } = {}
	local events: { [string]: boolean } = {}
	local eventOrder: { string } = {}
	local errorCount = 0
	local function report(renderer: string, id: number, operation: string, detail: any)
		-- Failures must be observable, but a broken renderer cannot flood Output each frame.
		if errorCount < 16 then
			errorCount += 1
			warn(
				string.format(
					"[EntityView] renderer=%s entity=%d operation=%s: %s",
					renderer,
					id,
					operation,
					tostring(detail)
				)
			)
		elseif errorCount == 16 then
			errorCount += 1
			warn("[EntityView] further adapter warnings suppressed for this view")
		end
	end
	local function cleanup(record: any, id: number)
		local ok, detail = true, nil
		if type(record.handle) == "table" and type(record.handle.destroy) == "function" then
			ok, detail = pcall(record.handle.destroy)
		end
		record.container:Destroy()
		if not ok then
			report(record.renderer, id, "destroy", detail)
		end
	end
	local function attempt(
		def: any,
		id: number,
		kind: string,
		team: string,
		renderer: string,
		factory: any
	): any
		local container = Instance.new("Folder")
		container.Name = "Entity_" .. id .. "_" .. renderer
		container.Parent = parent
		local ok, handle = pcall(factory, container, def, id, team, kind)
		local valid = ok
			and type(handle) == "table"
			and type(handle.update) == "function"
			and type(handle.destroy) == "function"
		if not valid then
			local detail = if ok
				then "invalid adapter handle (update/destroy functions required): " .. tostring(
					handle
				)
				else handle
			cleanup({ handle = handle, container = container, renderer = renderer }, id)
			report(renderer, id, "create", detail)
			if renderer == "Placeholder" then
				error(detail, 0)
			end
			return nil
		end
		return {
			handle = handle,
			container = container,
			renderer = renderer,
			definitionId = "",
			kind = kind,
			team = team,
		}
	end
	local function destroy(entityId: number)
		local record = records[entityId]
		if record then
			records[entityId] = nil
			cleanup(record, entityId)
		end
	end
	local function create(
		definitionId: string,
		_presentationId: string?,
		id: number,
		kind: string,
		team: string,
		renderer: string?
	): any
		destroy(id)
		local def = Definitions.resolve(definitionId, kind)
		local available: { [string]: boolean } = {}
		for name in factories do
			available[name] = true
		end
		-- Missing Sprite/Model stubs are expected and intentionally do not emit warnings.
		local selected = Definitions.chooseRenderer(renderer, available)
		local record = attempt(def, id, kind, team, selected, factories[selected])
			or attempt(def, id, kind, team, "Placeholder", placeholder)
		record.definitionId = definitionId
		records[id] = record
		return record
	end
	local function fallback(record: any, id: number)
		cleanup(record, id)
		local replacement = attempt(
			Definitions.resolve(record.definitionId, record.kind),
			id,
			record.kind,
			record.team,
			"Placeholder",
			placeholder
		)
		record.handle, record.container, record.renderer =
			replacement.handle, replacement.container, replacement.renderer
	end
	local function update(snapshot: any, alpha: number)
		local id = snapshot.entityId
		local record = records[id]
			or create(
				snapshot.definitionId,
				nil,
				id,
				snapshot.kind or "Projectile",
				snapshot.team or "Ally",
				snapshot.renderer
			)
		local ok, detail = pcall(record.handle.update, snapshot, alpha)
		if not ok then
			report(record.renderer, id, "update", detail)
			if record.renderer == "Placeholder" then
				error(detail, 0)
			end
			fallback(record, id)
			-- Placeholder defects are programmer errors, not silently swallowed renderer failures.
			record.handle.update(snapshot, alpha)
		end
		record.lastSnapshot = snapshot
	end
	local function play(
		entityId: number,
		eventId: string,
		state: string,
		startTick: number,
		durationTicks: number
	)
		local record = records[entityId]
		local eventKey = tostring(entityId) .. ":" .. eventId
		if not record or events[eventKey] then
			return
		end
		events[eventKey] = true
		table.insert(eventOrder, eventKey)
		if #eventOrder > 128 then
			local expired = table.remove(eventOrder, 1)
			if expired then
				events[expired] = nil
			end
		end
		if record.handle.play then
			local ok, detail = pcall(record.handle.play, eventId, state, startTick, durationTicks)
			if not ok then
				report(record.renderer, entityId, "play", detail)
				if record.renderer == "Placeholder" then
					error(detail, 0)
				end
				fallback(record, entityId)
				if record.lastSnapshot then
					record.handle.update(record.lastSnapshot, 1)
				end
			end
		end
	end
	local function sync(entities: { any }, projectiles: { any })
		local seen: { [number]: boolean } = {}
		for _, list in { entities, projectiles } do
			for _, snapshot in list do
				seen[snapshot.entityId] = true
				update(snapshot, 1)
			end
		end
		for id in records do
			if not seen[id] then
				destroy(id)
			end
		end
	end
	local function clear()
		for id in records do
			destroy(id)
		end
		table.clear(events)
		table.clear(eventOrder)
	end
	local function inspect(): any
		local result: { [number]: any } = {}
		for id, record in records do
			result[id] = { renderer = record.renderer, definitionId = record.definitionId }
		end
		return result
	end
	return {
		create = create,
		update = update,
		play = play,
		destroy = destroy,
		sync = sync,
		clear = clear,
		inspect = inspect,
	}
end
return table.freeze({ new = new, part = part })
