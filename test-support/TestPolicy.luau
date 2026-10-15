--!strict
-- Add only a separately approved TEST universe id; never production.
-- 10771015944: user-approved test universe (2026-10-15).
return table.freeze({ allowedUniverseIds = { 10771015944 } :: { number } })
