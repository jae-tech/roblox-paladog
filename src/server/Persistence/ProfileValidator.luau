--!strict
-- Reject malformed/cyclic/non-serializable documents before acquiring a lock or applying a transform.
local Schema = require("../Services/ProfileSchema")

local function validate(value: any): (boolean, string?)
	local bytes, nodes = 0, 0
	local seen: { [any]: boolean } = {}
	local function visit(item: any, depth: number): boolean
		nodes += 1
		if nodes > 8192 or depth > 16 then
			return false
		end
		local kind = type(item)
		if kind == "table" then
			if seen[item] then
				return false
			end
			seen[item] = true
			bytes += 2
			local strings, numbers, lastIndex = 0, 0, 0
			for key, child in item do
				if type(key) ~= "string" and type(key) ~= "number" then
					return false
				end
				if type(key) == "number" then
					if key % 1 ~= 0 or key < 1 or key > 8192 then
						return false
					end
					numbers += 1
					lastIndex = math.max(lastIndex, key)
				else
					strings += 1
				end
				if not visit(key, depth + 1) or not visit(child, depth + 1) then
					return false
				end
				bytes += 2
			end
			if (strings > 0 and numbers > 0) or lastIndex ~= numbers then
				return false
			end
		elseif kind == "string" then
			bytes += #item * 6 + 2 -- conservative JSON escaping bound, not a claim about actual encoded size
		elseif kind == "number" then
			if item ~= item or math.abs(item) == math.huge then
				return false
			end
			bytes += 32
		elseif kind == "boolean" or kind == "nil" then
			bytes += 5
		else
			return false
		end
		return bytes <= 65536
	end
	if not visit(value, 0) then
		return false, "not a bounded serializable profile"
	end
	local ok, valid, reason = pcall(Schema.validate, value)
	if not ok or not valid then
		return false, if ok then reason else "malformed profile"
	end
	local lease = value.lease
	if
		lease
		and (type(lease.ownerJobId) ~= "string" or lease.expiresAt % 1 ~= 0 or lease.expiresAt < 0)
	then
		return false, "invalid lease"
	end
	return true, nil
end

return table.freeze({ validate = validate })
