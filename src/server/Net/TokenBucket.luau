--!strict
-- Per-player rate limiter. `now` is a monotonic seconds clock supplied by the caller.
export type Bucket = { tokens: number, updatedAt: number, rate: number, burst: number }

local function new(rate: number, burst: number, now: number): Bucket
	return { tokens = burst, updatedAt = now, rate = rate, burst = burst }
end

local function refill(bucket: Bucket, now: number)
	if now > bucket.updatedAt then
		bucket.tokens =
			math.min(bucket.burst, bucket.tokens + (now - bucket.updatedAt) * bucket.rate)
		bucket.updatedAt = now
	end
end

local function take(bucket: Bucket, now: number): boolean
	refill(bucket, now)
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

local function retryAfter(bucket: Bucket, now: number): number
	refill(bucket, now)
	return if bucket.tokens >= 1 then 0 else (1 - bucket.tokens) / bucket.rate
end

return table.freeze({ new = new, take = take, retryAfter = retryAfter })
