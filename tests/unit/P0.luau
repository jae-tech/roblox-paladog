--!strict
-- Dependency injection keeps this exact suite usable in Luau CLI and Studio.
return function(
	fixtures: {
		clock: (number?) -> { now: () -> number, stepTicks: (number) -> () },
		rng: ({ number }) -> { nextInteger: (number, number) -> number },
		store: (
		) -> {
			backend: string,
			read: (string) -> { [string]: number }?,
			write: (string, { [string]: number }) -> (),
		},
	},
	check: (string, unknown, unknown, number) -> ()
)
	local clock = fixtures.clock(0)
	clock.stepTicks(20)
	check("fake-clock-ticks", 20, clock.now(), 20)
	check("fake-clock-reject-negative", false, pcall(clock.stepTicks, -1), 20)
	local rng = fixtures.rng({ 3, 1 })
	check("fake-rng-first", 3, rng.nextInteger(1, 3), 20)
	check("fake-rng-second", 1, rng.nextInteger(1, 3), 20)
	check("fake-rng-exhausted", false, pcall(rng.nextInteger, 1, 3), 20)
	local store = fixtures.store()
	check("store-explicit-mock", "Mock/InMemory", store.backend, 20)
	check("store-missing", nil, store.read("qa:a"), 20)
	local input = { gold = 0 }
	store.write("qa:a", input)
	input.gold = 999
	local loaded = store.read("qa:a")
	assert(loaded, "fixture record missing")
	check("store-write-detached", 0, loaded.gold, 20)
	loaded.gold = 888
	local reloaded = store.read("qa:a")
	assert(reloaded, "fixture record missing")
	check("store-read-detached", 0, reloaded.gold, 20)
	check("store-key-isolation", nil, store.read("qa:b"), 20)
end
