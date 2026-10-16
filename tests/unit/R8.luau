--!strict
-- R8 plaza (D-PLAZA-01/02): leaderboard stats and ranking from real v2 profiles.
return function(env: any, check: any)
	local Board, Schema = env.PlazaBoard, env.Schema
	local empty = Board.statsOf(Schema.newProfile())
	check("board-no-slot-level", 0, empty.level, 0)
	check("board-no-slot-stage", 0, empty.stage, 0)
	check("board-nil-profile", 0, Board.statsOf(nil).stage, 0)

	local p = Schema.newProfile()
	p.slots[1], p.currentSlot = Schema.newSlot("light", 1), 1
	local slot = p.slots[1]
	slot.stars[1], slot.stars[2], slot.stars[30] = 3, 1, 0
	slot.level, slot.survivalBest = 17, 42
	local s = Board.statsOf(p)
	check("board-highest-cleared", 2, s.stage, 0)
	check("board-level", 17, s.level, 0)
	check("board-wave", 42, s.wave, 0)
	slot.stars[30] = 1
	check("board-chapter2", 30, Board.statsOf(p).stage, 0)
	check("board-label-1-1", "1-1", Board.stageLabel(1), 0)
	check("board-label-2-6", "2-6", Board.stageLabel(30), 0)
	check("board-label-5-24", "5-24", Board.stageLabel(120), 0)
	check("board-label-none", "-", Board.stageLabel(0), 0)

	local rows = {}
	for i = 1, 14 do
		table.insert(
			rows,
			{ userId = 100 + i, name = "p" .. i, level = i, stage = i % 5, wave = 0 }
		)
	end
	table.insert(rows, { userId = 1, name = "wave", level = 1, stage = 4, wave = 9 })
	local ranked = Board.rank(rows)
	check("board-capped", Board.BOARD_SIZE, #ranked, 0)
	check("board-top-stage", 4, ranked[1].stage, 0)
	check("board-wave-breaks-tie", "wave", ranked[1].name, 0)
	check("board-level-breaks-tie", "p14", ranked[2].name, 0)
	local ordered = true
	for i = 2, #ranked do
		if ranked[i - 1].stage < ranked[i].stage then
			ordered = false
		end
	end
	check("board-descending", true, ordered, 0)
	check("board-input-untouched", 15, #rows, 0)
end
