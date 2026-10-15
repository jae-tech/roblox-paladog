--!strict
return function(
	isStudio: boolean,
	hasTestMarker: boolean,
	universeId: number,
	allowed: { number }
): boolean
	return isStudio and hasTestMarker and table.find(allowed, universeId) ~= nil
end
