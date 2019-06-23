local addon, ns = ...

--------------------------------------
--	Settings
--------------------------------------
-- debug
local isDebug = false
local debugLevel = 2

-- log formatting
local localizedStrings = false
local logVersion = 2

--------------------------------------
--	Init
--------------------------------------
-- SavedVariables
MageyLogData = MageyLogData or {}

-- get locale
local locale = GetLocale()

-- setup time
local currentTime = date("%Y/%m/%d %H:%M:%S.000")
local currentTimeMS = time()

-- event frame
local DataCollector = CreateFrame("Frame")

-- init player/target collection tables
DataCollector.player = {}
DataCollector.target = {}

--------------------------------------
--	Event Registry
--------------------------------------
-- gather player name/GUID/level/stats
DataCollector:RegisterEvent("PLAYER_ENTERING_WORLD")
DataCollector:RegisterEvent("PLAYER_LEVEL_UP")
DataCollector:RegisterEvent("PLAYER_LEVEL_CHANGED")

-- gather player stat changes
DataCollector:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
DataCollector:RegisterEvent("UNIT_AURA")
DataCollector:RegisterEvent("CHAT_MSG_SKILL")
DataCollector:RegisterEvent("SKILL_LINES_CHANGED")

-- gather target name/GUID/level
DataCollector:RegisterEvent("PLAYER_TARGET_CHANGED")

-- trigger CLEU for melee events
DataCollector:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

--------------------------------------
--	Strings
--------------------------------------
local PLAYER		= localizedStrings and PLAYER				or "Player"
local TARGET		= localizedStrings and TARGET				or "Target"
local HIT			= localizedStrings and HIT					or "Hit" 
local CRIT			= localizedStrings and CRIT_ABBR			or "Crit"
local MISS			= localizedStrings and MISS					or "Miss"
local PARRY			= localizedStrings and PARRY				or "Parry"
local SPELL			= localizedStrings and STAT_CATEGORY_SPELL	or "Spell"

local MH			= "MH_"
local OH			= "OH_"
local SPELLCRIT		= SPELL.."_"..CRIT
local SPELLMISS		= SPELL.."_"..MISS
local SPELLPARRY	= SPELL.."_"..PARRY

PLAYER				= string.upper(PLAYER)
TARGET				= string.upper(TARGET)
HIT					= string.upper(HIT)
CRIT				= string.upper(CRIT)
MISS				= string.upper(MISS)
PARRY				= string.upper(PARRY)
SPELL				= string.upper(SPELL)
SPELLCRIT			= string.upper(SPELLCRIT)
SPELLMISS			= string.upper(SPELLMISS)
SPELLPARRY			= string.upper(SPELLPARRY)

if logVersion == 2 then
	PLAYER			= "PLAYER_STATS_CHANGED"
	TARGET			= "PLAYER_TARGET_CHANGED"
end

local playerFormat	= "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" -- 12
local targetFormat	= "%s,%s,%s,%s,%s" -- 5

--------------------------------------
--	Utility
--------------------------------------
-- check if Classic or BfA
local function IsClassic()
	if select(4, GetBuildInfo()) < 2e4-1 then return true end
end

-- debug
local function debug(msg1, msg2)
	if not isDebug then return end
	print("|cfff00000"..addon..": "..msg1.."|r")

	if debugLevel > 1 and msg2 then
		print("|cfff00000"..msg2.."|r")
	end
end

-- compare tables
local function CompareTable(t1, t2, ignore_mt)
	local ty1 = type(t1)
	local ty2 = type(t2)
	if ty1 ~= ty2 then return false end
	if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
	local mt = getmetatable(t1)
	if not ignore_mt and mt and mt.__eq then return t1 == t2 end
	for k1, v1 in pairs(t1) do
	local v2 = t2[k1]
	if v2 == nil or not CompareTable(v1, v2) then return false end
	end
	for k2, v2 in pairs(t2) do
	local v1 = t1[k2]
	if v1 == nil or not CompareTable(v1, v2) then return false end
	end
	return true
end

--------------------------------------
--	Stat Functions
--------------------------------------
local function GetWeaponType()
	local mainWeaponType, offWeaponType
	local mainWeaponItemID, offWeaponItemID = GetInventoryItemID("player", 16), GetInventoryItemID("player", 17)

	-- locale support (untested in non-English clients)
	local oneHand
	if locale == "enUS" or locale == "enGB" then
		oneHand = "One%-Handed "
	elseif locale == "zhCN" or locale == "zhTW" then
		oneHand = AUCTION_SUBCATEGORY_ONE_HANDED
	elseif locale == "deDE" then
		oneHand = "Zweihändige "
	elseif locale == "esES" or locale == "esMX" or locale == "ptPT" or locale == "ptBR" then
		oneHand = " de "..AUCTION_SUBCATEGORY_ONE_HANDED
	elseif locale == "frFR" then
		oneHand = " à "..AUCTION_SUBCATEGORY_ONE_HANDED
	elseif locale == "itIT" then
		oneHand = " a "..AUCTION_SUBCATEGORY_ONE_HANDED
	elseif locale == "koKR" then
		oneHand = "양손 "
	elseif locale == "ruRU" then
		oneHand = AUCTION_SUBCATEGORY_ONE_HANDED.." "
	end

	-- get weapon type(s)
	if mainWeaponItemID then
		mainWeaponType = select(7, GetItemInfo(mainWeaponItemID))
	end
	if offWeaponItemID then
		offWeaponType = select(7, GetItemInfo(offWeaponItemID))
	end

	-- get localized string by looking up info with the Unarmed spellID
	local unarmed = GetSpellInfo(203)

	-- pass "Unarmed" string along if needed
	mainWeaponType = mainWeaponType or unarmed
	offWeaponType = mainWeaponType or unarmed

	-- strip "One-Handed" from weapon type(s) to compare with weapon skill(s)
	if string.find(mainWeaponType, oneHand) then
		mainWeaponType = string.gsub(mainWeaponType, oneHand, "")
	end
	if string.find(offWeaponType, oneHand) then
		offWeaponType = string.gsub(offWeaponType, oneHand, "")
	end

	return mainWeaponType, offWeaponType
end

local function GetWeaponSkill()
	local mainWeaponType, offWeaponType = GetWeaponType()
	local mainSkill, offSkill

	local numSkills = GetNumSkillLines()
	for i = 1, numSkills do
		local skillName, isHeader, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank, isAbandonable, stepCost, rankCost, minLevel, skillCostType, skillDescription = GetSkillLineInfo(i)

		if skillName == mainWeaponType then
			mainSkill = skillRank + numTempPoints + skillModifier
		end

		if skillName == offWeaponType then
			offSkill = skillRank + numTempPoints + skillModifier
		end
	end

	return mainSkill, offSkill
end

local function GetAttackPower()
	local base, posBuff, negBuff = UnitAttackPower("player")
	local effective = base + posBuff + negBuff

	return effective
end

function GetPlayerCritChance()
	return tonumber(string.format("%.4f", GetCritChance()))
end

--------------------------------------
--	Workers
--------------------------------------
function DataCollector:GetPlayerStats()
	self.player.name = UnitName("player")
	self.player.guid = UnitGUID("player")
	self.player.level = UnitLevel("player")
	if IsClassic() then
		local mhType, ohType = GetWeaponType()
		local mhSkill, ohSkill = GetWeaponSkill()

		self.player.mainWeaponType	= mhType or nil
		self.player.offWeaponType	= ohType or nil
		self.player.mainWeaponSkill	= mhSkill or nil
		self.player.offWeaponSkill	= ohSkill or nil
	end
	self.player.ap = GetAttackPower() or nil
	self.player.crit = GetPlayerCritChance() or nil
	self.player.hit = GetHitModifier() or nil

	-- emulate WoWCombatLog.txt for log v2
	if logVersion == 2 then
		self.player.name = "'"..self.player.name.."'"
	end

	-- debug
	debug("Player stats collected.", format(playerFormat, currentTime, PLAYER, tostringall(self.player.guid, self.player.name, self.player.level, self.player.mainWeaponType, self.player.offWeaponType, self.player.mainWeaponSkill, self.player.offWeaponSkill, self.player.ap, self.player.crit, self.player.hit)))
end

function DataCollector:GetTargetStats()
	-- only update if there is a valid target
	if not UnitExists("target") or not UnitCanAttack("player", "target") then return end

	self.target.name = UnitName("target") or nil
	self.target.guid = UnitGUID("target") or nil
	self.target.level = UnitLevel("target") or nil

	-- emulate WoWCombatLog.txt for log v2
	if logVersion == 2 then
		self.target.name = "'"..self.target.name.."'"
	end

	-- debug
	debug("Target stats collected.", format(targetFormat, currentTime, TARGET, tostringall(self.target.guid, self.target.name, self.target.level)))
end

function DataCollector:LogToSavedVariables(currentTime, logType, ...)
	-- shared local
	local logString

	if logType == PLAYER then
		-- set log string
		logString = format(playerFormat, currentTime, PLAYER, tostringall(self.player.guid, self.player.name, self.player.level, self.player.mainWeaponType, self.player.offWeaponType, self.player.mainWeaponSkill, self.player.offWeaponSkill, self.player.ap, self.player.crit, self.player.hit))

		-- insert entry into the SavedVariables log
		tinsert(MageyLogData, logString)

		-- debug
		debug(logType.." logged.", logString)
	elseif logType == TARGET then
		-- set log string
		logString = format(targetFormat, currentTime, logType, tostringall(self.target.guid, self.target.name, self.target.level))

		-- insert entry into the SavedVariables log
		tinsert(MageyLogData, logString)

		-- debug
		debug(logType.." logged.", logString)
	end
		
	-- we're done here if there was no combat event
	if logType == PLAYER or logType == TARGET then return end

	if logVersion == 1 then
		--locals
		local destGUID
		local spellID, spellName, spellSchool
		local amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand
		local missType, amountMissed
	
		if logType == HIT then
			destGUID, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = ...

			-- change logType to CRIT if the hit was critical
			if critical then logType = CRIT end

			-- change logType to indicate main-hand / off-hand
			if isOffHand then
				logType = OH..logType
			else
				logType = MH..logType
			end

			-- set log string
			logString = format("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", currentTime, logType, tostringall(amount, overkill, school, resisted, blocked, absorbed, glancing, crushing))
		elseif logType == MISS then
			-- get variable arguments
			destGUID, missType, isOffHand, amountMissed = ...

			-- only log misses if the combat log event is against our current target
			if destGUID ~= self.target.guid then return end

			-- change logType to indicate main-hand / off-hand
			if isOffHand then
				logType = OH..logType
			else
				logType = MH..logType
			end

			-- set log string
			logString = format("%s,%s,%s,%s", currentTime, logType, tostringall(missType, amountMissed))
		elseif logType == PARRY then
			-- get variable arguments
			destGUID, amountMissed = ...

			-- only log parrys if the combat log event is against the player
			if destGUID ~= self.target.player then return end

			-- set log string
			logString = format("%s,%s,%s", currentTime, logType, tostringall(amountMissed))
		elseif logType == SPELL then
			-- get variable arguments
			destGUID, spellID, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = ...

			-- change logType to CRIT if the hit was critical
			if critical then logType = CRIT end

			-- change logType to indicate main-hand / off-hand
			if isOffHand then
				logType = OH..logType
			else
				logType = MH..logType
			end

			-- set log string
			logString = format("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", currentTime, logType, tostringall(spellID, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing))
		elseif logType == SPELLMISS then
			-- get variable arguments
			destGUID, spellID, spellName, spellSchool, missType, isOffHand, amountMissed = ...

			-- change logType to indicate main-hand / off-hand
			if isOffHand then
				logType = OH..logType
			else
				logType = MH..logType
			end

			-- set log string
			logString = format("%s,%s,%s,%s,%s,%s,%s", currentTime, logType, tostringall(spellID, spellName, spellSchool, missType, amountMissed))
		elseif logType == SPELLPARRY then
			-- get variable arguments
			destGUID, spellID, spellName, spellSchool, amountMissed = ...

			-- only log parrys if the combat log event is against the player
			if destGUID ~= self.target.player then return end

			-- set log string
			logString = format("%s,%s,%s,%s,%s,%s", currentTime, logType, tostringall(spellID, spellName, spellSchool, amountMissed))
		end
	elseif logVersion == 2 then
		-- shared arguments
		local sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = select(2, ...)

		-- locals
		local spellID, spellName, spellSchool
		local amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand
		local missType, amountMissed

		-- 24 returns from CLEU (but we exclude hideCaster to match WoWCombatLog.txt - https://wow.gamepedia.com/COMBAT_LOG_EVENT
		local swingHitFormat	= "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" -- 20
		local swingMissFormat	= "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" -- 13
		local spellHitFormat	= "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" -- 23
		local spellMissFormat	= "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" -- 16

		-- emulate WoWCombatLog.txt
		sourceName		= "'"..sourceName.."'"
		sourceFlags		= string.format("0x%x", sourceFlags)
		sourceRaidFlags	= string.format("0x%x", sourceRaidFlags)
		destName		= "'"..destName.."'"
		destFlags		= string.format("0x%x", destFlags)
		destRaidFlags	= string.format("0x%x", destRaidFlags)

		if logType == "SWING_DAMAGE" then
			amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = select(10, ...)

			-- set log string
			logString = format(swingHitFormat, currentTime, logType, tostringall(sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand))
		elseif logType == "SWING_MISSED" then
			missType, isOffHand, amountMissed = select(10, ...)

			-- set log string
			logString = format(swingMissFormat, currentTime, logType, tostringall(sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, missType, isOffHand, amountMissed))
		elseif logType == "SPELL_DAMAGE" then
			spellID, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = select(10, ...)

			-- emulate WoWCombatLog.txt
			spellName = "'"..spellName.."'"

			-- set log string
			logString = format(spellHitFormat, currentTime, logType, tostringall(sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand))
		elseif logType == "SPELL_MISSED" then
			spellID, spellName, spellSchool, missType, isOffHand, amountMissed = select(10, ...)

			-- emulate WoWCombatLog.txt
			spellName = "'"..spellName.."'"

			-- set log string
			logString = format(spellMissFormat, currentTime, logType, tostringall(sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool, missType, isOffHand, amountMissed))
		end
	end

	if logString then
		-- insert entry into the SavedVariables log
		tinsert(MageyLogData, logString)

		-- debug
		debug(logType.." logged.", logString)
	end
end

DataCollector:SetScript("OnEvent", function(self, event, ...)
	-- update currentTime if needed
	if time() > tonumber(currentTimeMS) then
		currentTime = date("%Y/%m/%d %H:%M:%S.000") -- time() fallback when CLEU timestamp is not available
	end

	-- handle events
	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_LEVEL_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_AURA" or event == "CHAT_MSG_SKILL" or event == "SKILL_LINES_CHANGED" then
		-- make sure we are set up on login / after loading screens
		if event == "PLAYER_ENTERING_WORLD" then
			-- auto start combat log / set advanced logging
			if not LoggingCombat() then
				LoggingCombat(1)
				print("|cffffff00"..COMBATLOGENABLED.."|r")
			end
			SetCVar("advancedCombatLogging", 1)
		end

		-- only check for aura changes when event is fired for the player
		if event == "UNIT_AURA" then
			local unitTarget = ...
			if unitTarget ~= "player" then return end
		end

		-- only check for weapon skill changes when relevant messages are received
		if event == "CHAT_MSG_SKILL" then
			local msg = ...
			if msg ~= ERR_SKILL_GAINED_S or msg ~= ERR_SKILL_UP_SI then return end
		end
		
		-- only log if there is new player info
		local oldPlayerStats = CopyTable(self.player)
		self:GetPlayerStats()
		if CompareTable(oldPlayerStats, self.player) == false then
			self:LogToSavedVariables(currentTime, PLAYER)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- only log if there is new target info
		local oldTargetStats = CopyTable(self.target)
		self:GetTargetStats()
		if CompareTable(oldTargetStats, self.target) == false then
			self:LogToSavedVariables(currentTime, TARGET)
		end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		-- get shared arguments
		local timestamp, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

		-- use timestamp for currentTime / update currentTimeMS
		currentTimeMS = timestamp
		currentTime = date("%Y/%m/%d %H:%M:%S", currentTimeMS)
		currentTime = currentTime..string.sub(string.format("%.3f", currentTimeMS % 1), 2)

		-- skip if event where the player is not the source or destination
		if sourceGUID ~= self.player.guid and destGUID ~= self.player.guid then return end

		-- locals for subEvent specific arguments
		local spellID, spellName, spellSchool
		local amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand
		local missType, amountMissed

		if subEvent == "SWING_DAMAGE" then
			-- only log if the combat log event is against our current target
			if destGUID ~= self.target.guid then return end

			-- get subEvent specific arguments
			amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = select(12, CombatLogGetCurrentEventInfo())

			-- log
			if logVersion == 1 then
				self:LogToSavedVariables(currentTime, HIT, destGUID, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand)
			elseif logVersion == 2 then
				self:LogToSavedVariables(currentTime, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand)
			end
		elseif subEvent == "SWING_MISSED" then
			-- get subEvent specific arguments
			missType, isOffHand, amountMissed = select(12, CombatLogGetCurrentEventInfo())

			-- player miss against target / player parry from enemy
			if destGUID == self.player.guid and missType == "PARRY" then
				-- log
				if logVersion == 1 then
					self:LogToSavedVariables(currentTime, PARRY, destGUID, amountMissed)
				elseif logVersion == 2 then
					self:LogToSavedVariables(currentTime, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, missType, isOffHand, amountMissed)
				end
			else
				-- skip if swing didn't come from the player
				if sourceGUID ~= self.player.guid then return end

				-- log
				if logVersion == 1 then
					self:LogToSavedVariables(currentTime, MISS, destGUID, missType, isOffHand, amountMissed)
				elseif logVersion == 2 then
					self:LogToSavedVariables(currentTime, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, missType, isOffHand, amountMissed)
				end
			end
		elseif subEvent == "SPELL_DAMAGE" then
			-- only log if the combat log event is against our current target
			if destGUID ~= self.target.guid then return end

			-- get subEvent specific arguments
			spellID, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = select(12, CombatLogGetCurrentEventInfo())

			-- log
			if logVersion == 1 then
				self:LogToSavedVariables(currentTime, SPELL, destGUID, spellID, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand)
			elseif logVersion == 2 then
				self:LogToSavedVariables(currentTime, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand)
			end
		elseif subEvent == "SPELL_MISSED" then
			-- get subEvent specific arguments
			spellID, spellName, spellSchool, missType, isOffHand, amountMissed = select(12, CombatLogGetCurrentEventInfo())

			-- player miss against target / player parry from enemy
			if destGUID == self.player.guid and missType == "PARRY" then
				-- log
				if logVersion == 1 then
					self:LogToSavedVariables(currentTime, SPELLPARRY, destGUID, spellID, spellName, spellSchool, amountMissed)
				elseif logVersion == 2 then
					self:LogToSavedVariables(currentTime, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool, missType, isOffHand, amountMissed)
				end
			else
				-- skip if swing didn't come from the player
				if sourceGUID ~= self.player.guid then return end

				-- log
				if logVersion == 1 then
					self:LogToSavedVariables(currentTime, SPELLMISS, destGUID, spellID, spellName, spellSchool, missType, isOffHand, amountMissed)
				elseif logVersion == 2 then
					self:LogToSavedVariables(currentTime, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool, missType, isOffHand, amountMissed)
				end
			end
		end
	end
end)
