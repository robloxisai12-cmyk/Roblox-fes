--!strict

type RateBucket = {
	WindowStartedAt: number,
	Count: number,
}

local CombatRules = {}

function CombatRules.CanFire(
	lastShotAt: number?,
	now: number,
	fireInterval: number,
	magazine: number,
	isReloading: boolean,
	isAlive: boolean
): (boolean, string)
	if not isAlive then
		return false, "attacker_unavailable"
	end
	if isReloading then
		return false, "reloading"
	end
	if magazine <= 0 then
		return false, "no_ammo"
	end
	if lastShotAt ~= nil and now - lastShotAt < fireInterval then
		return false, "rate_limited"
	end
	return true, "ready"
end

function CombatRules.TakeRateLimitToken(
	bucket: RateBucket?,
	now: number,
	windowSeconds: number,
	maxRequests: number
): (boolean, RateBucket)
	if bucket == nil or now - bucket.WindowStartedAt >= windowSeconds then
		return true, {
			WindowStartedAt = now,
			Count = 1,
		}
	end
	if bucket.Count >= maxRequests then
		return false, bucket
	end

	return true, {
		WindowStartedAt = bucket.WindowStartedAt,
		Count = bucket.Count + 1,
	}
end

function CombatRules.IsWithinRange(distance: number, maxRange: number): boolean
	return distance == distance
		and distance >= 0
		and distance < math.huge
		and maxRange > 0
		and distance <= maxRange
end

function CombatRules.CanDamageTarget(
	attackerCharacter: any,
	targetCharacter: any,
	hasHumanoid: boolean,
	hasRootPart: boolean,
	targetHealth: number
): boolean
	return attackerCharacter ~= nil
		and targetCharacter ~= nil
		and targetCharacter ~= attackerCharacter
		and hasHumanoid
		and hasRootPart
		and targetHealth == targetHealth
		and targetHealth > 0
end

function CombatRules.CalculateDamage(targetHealth: number, configuredDamage: number): number
	if targetHealth ~= targetHealth
		or configuredDamage ~= configuredDamage
		or targetHealth <= 0
		or configuredDamage <= 0
		or targetHealth == math.huge
		or configuredDamage == math.huge
	then
		return 0
	end
	return math.min(targetHealth, configuredDamage)
end

return table.freeze(CombatRules)
