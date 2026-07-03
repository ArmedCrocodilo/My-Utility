--!nonstrict

local RATE_MODES = {
	Debounce = 1,
	Rate = 2,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type ClassProperties = {
	mode: number,
	limit: number,
	window: number,
	nextAllowedAt: number,
	tokens: number,
	lastRefillAt: number,
	destroyed: boolean,
}

export type RateLimiter = setmetatable<ClassProperties, typeof(RateLimiter)>

local function now(): number
	return os.clock()
end

local function init(self: RateLimiter)
	self.mode = RATE_MODES.Debounce
	self.limit = 1
	self.window = 1
	self.nextAllowedAt = 0
	self.tokens = 1
	self.lastRefillAt = now()
	self.destroyed = false
end

function RateLimiter.setMode(self: RateLimiter, mode: number)
	self.mode = mode
end

function RateLimiter.setCooldown(self: RateLimiter, cooldown: number)
	self.limit = 1
	self.window = math.max(cooldown, 0)
	self.nextAllowedAt = 0
	self.tokens = 1
	self.lastRefillAt = now()
end

function RateLimiter.setRate(self: RateLimiter, limit: number, window: number)
	self.limit = math.max(math.floor(limit), 1)
	self.window = math.max(window, 0.0001)
	self.tokens = math.min(self.tokens, self.limit)
	self.lastRefillAt = now()
end

function RateLimiter.reset(self: RateLimiter)
	self.nextAllowedAt = 0
	self.tokens = self.limit
	self.lastRefillAt = now()
end

function RateLimiter.isLimiting(self: RateLimiter): boolean
	if self.destroyed then
		return true
	end

	return self:getTimeLeft() > 0
end

function RateLimiter.getTimeLeft(self: RateLimiter): number
	if self.destroyed then
		return math.huge
	end

	local currentTime = now()

	if self.mode == RATE_MODES.Debounce then
		return math.max(self.nextAllowedAt - currentTime, 0)
	end

	if self.tokens >= 1 then
		return 0
	end

	local refillPerSecond = self.limit / self.window
	if refillPerSecond <= 0 then
		return math.huge
	end

	return math.max((1 - self.tokens) / refillPerSecond, 0)
end

function RateLimiter.tryExecute(self: RateLimiter): boolean
	if self.destroyed then
		return false
	end

	local currentTime = now()

	if self.mode == RATE_MODES.Debounce then
		if currentTime < self.nextAllowedAt then
			return false
		end

		self.nextAllowedAt = currentTime + self.window
		return true
	end

	local deltaTime = currentTime - self.lastRefillAt
	self.lastRefillAt = currentTime

	local refillAmount = (self.limit / self.window) * deltaTime
	self.tokens = math.min(self.limit, self.tokens + refillAmount)

	if self.tokens < 1 then
		return false
	end

	self.tokens -= 1
	return true
end

function RateLimiter.tryCall<T..., R...>(self: RateLimiter, callback: (T...) -> R..., ...: T...): (boolean, R...)
	if not self:tryExecute() then
		return false
	end

	return true, callback(...)
end

function RateLimiter.destroy(self: RateLimiter)
	self.destroyed = true
end

local function new(mode: number?, limit: number?, window: number?): RateLimiter
	local self = setmetatable({} :: ClassProperties, RateLimiter)

	init(self)

	if mode ~= nil then
		self.mode = mode
	end

	if limit ~= nil then
		self.limit = math.max(math.floor(limit), 1)
	end

	if window ~= nil then
		self.window = math.max(window, 0.0001)
	end

	if self.mode == RATE_MODES.Rate then
		self.tokens = self.limit
		self.lastRefillAt = now()
	else
		self.nextAllowedAt = 0
	end

	return self
end

return table.freeze({
	new = new,
	RateMode = RATE_MODES,
})
