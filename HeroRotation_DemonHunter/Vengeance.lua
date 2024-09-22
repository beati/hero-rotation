--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroDBC
local DBC           = HeroDBC.DBC
-- HeroLib
local HL            = HeroLib
local Cache         = HeroCache
local Unit          = HL.Unit
local Player        = Unit.Player
local Target        = Unit.Target
local Pet           = Unit.Pet
local Spell         = HL.Spell
local Item          = HL.Item
-- HeroRotation
local HR            = HeroRotation
local AoEON         = HR.AoEON
local CDsON         = HR.CDsON
local Cast          = HR.Cast
local CastQueue     = HR.CastQueue
local CastSuggested = HR.CastSuggested
local CastAnnotated = HR.CastAnnotated
-- Num/Bool Helper Functions
local num           = HR.Commons.Everyone.num
local bool          = HR.Commons.Everyone.bool
-- lua
local GetTime       = GetTime
local mathfloor     = math.floor
local mathmax       = math.max
local mathmin       = math.min
local tableinsert   = table.insert

--- ============================ CONTENT ===========================
--- ======= APL LOCALS =======
-- luacheck: max_line_length 9999

-- Define S/I for spell and item arrays
local S = Spell.DemonHunter.Vengeance
local I = Item.DemonHunter.Vengeance

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {
  -- I.Item:ID(),
}

--- ===== GUI Settings =====
local Everyone = HR.Commons.Everyone
local DemonHunter   = HR.Commons.DemonHunter
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.DemonHunter.Commons,
  CommonsDS = HR.GUISettings.APL.DemonHunter.CommonsDS,
  CommonsOGCD = HR.GUISettings.APL.DemonHunter.CommonsOGCD,
  Vengeance = HR.GUISettings.APL.DemonHunter.Vengeance
}

--- ===== Rotation Variables =====
local SoulFragments, TotalSoulFragments, IncSoulFragments
local VarFieryBrandCD = (S.DowninFlames:IsAvailable()) and 48 or 60
local VarSigilPopTime = (S.QuickenedSigils:IsAvailable()) and 1 or 2
local VarSoFCD = (S.IlluminatedSigils:IsAvailable()) and 25 or 30
local VarSoSFragments = (S.SoulSigils:IsAvailable()) and 4 or 3
local IsInMeleeRange, IsInAoERange
local ActiveMitigationNeeded
local ImmoAbility
local IsTanking
local Enemies8yMelee
local EnemiesCount8yMelee
local VarNumSpawnableSouls = 0
local VarSpBThreshold, VarSpBombThreshold, VarSpBurstThreshold
local VarCanSpB, VarCanSpBSoon, VarCanSpBOneGCD
local VarCanSpBomb, VarCanSpBombSoon, VarCanSpBombOneGCD
local VarCanSpBurst, VarCanSpBurstSoon, VarCanSpBurstOneGCD
local VarDontSoulCleave, VarMetaPrepTime
local VarDoubleRMExpires, VarDoubleRMRemains
local VarRGSequenceDuration
local VarTriggerOverflow, VarRGEnhCleave, VarCDSync
local VarDSExecutionCost, VarDSExecuteTimeRemaining
local VarFBBeforeMeta, VarHoldSoFForMeta, VarHoldSoFForFelDev, VarHoldSoFForStudent, VarHoldSoFForDot, VarHoldSoFForPrecombat
local VarCritPct, VarFelDevSequenceTime, VarFelDevPassiveFuryGen
local VarST, VarSmallAoE, VarBigAoE
local BossFightRemains = 11111
local FightRemains = 11111

--- ===== Event Registrations =====
HL:RegisterForEvent(function()
  BossFightRemains = 11111
  FightRemains = 11111
end, "PLAYER_REGEN_ENABLED")

HL:RegisterForEvent(function()
  VarFieryBrandCD = (S.DowninFlames:IsAvailable()) and 48 or 60
  VarSigilPopTime = (S.QuickenedSigils:IsAvailable()) and 1 or 2
  VarSoFCD = (S.IlluminatedSigils:IsAvailable()) and 25 or 30
  VarSoSFragments = (S.SoulSigils:IsAvailable()) and 4 or 3
end, "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB")

--- ===== Helper Functions =====
-- Melee Is In Range w/ Movement Handlers
local function UpdateIsInMeleeRange()
  if S.Felblade:TimeSinceLastCast() < Player:GCD()
  or S.InfernalStrike:TimeSinceLastCast() < Player:GCD() then
    IsInMeleeRange = true
    IsInAoERange = true
    return
  end

  IsInMeleeRange = Target:IsInMeleeRange(5)
  IsInAoERange = IsInMeleeRange or EnemiesCount8yMelee > 0
end

-- We repeatedly check DarkglareBoon Fury levels, so let's make a function for it...
local function DGBFury(FuryWithDGB, FuryWithoutDGB)
  return ((S.DarkglareBoon:IsAvailable() and Player:Fury() >= FuryWithDGB) or (not S.DarkglareBoon:IsAvailable() and Player:Fury() >= FuryWithoutDGB))
end

--- ===== Rotation Functions =====
local function Precombat()
  -- flask
  -- augmentation
  -- food
  -- snapshot_stats
  -- variable,name=single_target,value=spell_targets.spirit_bomb=1
  -- variable,name=small_aoe,value=spell_targets.spirit_bomb>=2&spell_targets.spirit_bomb<=5
  -- variable,name=big_aoe,value=spell_targets.spirit_bomb>=6
  -- Note: Moving the above variables to APL()
  -- arcane_torrent
  if S.ArcaneTorrent:IsCastable() then
    if Cast(S.ArcaneTorrent, Settings.CommonsOGCD.OffGCDasOffGCD.Racials, nil, not Target:IsInRange(8)) then return "arcane_torrent precombat 2"; end
  end
  -- sigil_of_flame,if=hero_tree.aldrachi_reaver|(hero_tree.felscarred&talent.student_of_suffering)
  --if S.SigilofFlame:IsCastable() and (Player:HeroTreeID() == 35 or (Player:HeroTreeID() == 34 and S.StudentofSuffering:IsAvailable())) then
    --if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame precombat 4"; end
  --end
  -- Manually added: Gap closers
  --if S.InfernalStrike:IsCastable() and not IsInMeleeRange then
    --if Cast(S.InfernalStrike, Settings.Vengeance.OffGCDasOffGCD.InfernalStrike, nil, not Target:IsInRange(30)) then return "infernal_strike precombat 4"; end
  --end
  -- Note (Jom): Removed this from precombat because it harms the opener
  -- if S.Felblade:IsCastable() and not IsInMeleeRange then
  --   if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade precombat 6"; end
  -- end
  -- immolation_aura
  if ImmoAbility:IsCastable() then
    if Cast(ImmoAbility) then return "immolation_aura precombat 6"; end
  end
  -- Manually added: First attacks
  if S.Fracture:IsCastable() and IsInMeleeRange then
    if Cast(S.Fracture) then return "fracture precombat 10"; end
  end
  if S.Shear:IsCastable() and IsInMeleeRange then
    if Cast(S.Shear) then return "shear precombat 12"; end
  end
end

local function Defensives()
  -- Demon Spikes
  if S.DemonSpikes:IsCastable() and Player:BuffDown(S.DemonSpikesBuff) and Player:BuffDown(S.MetamorphosisBuff) and (EnemiesCount8yMelee == 1 and Player:BuffDown(S.FieryBrandDebuff) or EnemiesCount8yMelee > 1) then
    if S.DemonSpikes:ChargesFractional() > 1.9 then
      if Cast(S.DemonSpikes, nil, Settings.Vengeance.DisplayStyle.DemonSpikes) then return "demon_spikes defensives (Capped)"; end
    elseif (ActiveMitigationNeeded or Player:HealthPercentage() <= Settings.Vengeance.DemonSpikesHealthThreshold) then
      if Cast(S.DemonSpikes, nil, Settings.Vengeance.DisplayStyle.DemonSpikes) then return "demon_spikes defensives (Danger)"; end
    end
  end
  -- Metamorphosis,if=!buff.metamorphosis.up|target.time_to_die<15
  if S.Metamorphosis:IsCastable() and Player:HealthPercentage() <= Settings.Vengeance.MetamorphosisHealthThreshold and (Player:BuffDown(S.MetamorphosisBuff) or BossFightRemains < 15) then
    if Cast(S.Metamorphosis, nil, Settings.CommonsDS.DisplayStyle.Metamorphosis) then return "metamorphosis defensives"; end
  end
  -- Fiery Brand
  if S.FieryBrand:IsCastable() and (ActiveMitigationNeeded or Player:HealthPercentage() <= Settings.Vengeance.FieryBrandHealthThreshold) then
    if Cast(S.FieryBrand, nil, Settings.Vengeance.DisplayStyle.FieryBrand, not Target:IsSpellInRange(S.FieryBrand)) then return "fiery_brand defensives"; end
  end
end


local function SimplifiedAPL()
  -- Vars to calculate Fracture Fury gain
  local VarFractureFuryInMeta = 45
  local VarFractureFuryNotInMeta = 25
  local VarFractureFuryGain = 0
  if Player:BuffUp(S.MetamorphosisBuff) then
    VarFractureFuryGain = VarFractureFuryInMeta
  else
    VarFractureFuryGain = VarFractureFuryNotInMeta
  end

  if S.SpiritBurst:IsReady() and Player:Demonsurge("SpiritBurst") then
    if Cast(S.SpiritBurst, nil, nil, not Target:IsInMeleeRange(8)) then return "spirit_burst2"; end
  end

  if S.SoulSunder:IsReady() and Player:Demonsurge("SoulSunder") then
    if Cast(S.SoulSunder, nil, nil, not IsInMeleeRange) then return "soul_sunder"; end
  end

  if S.ReaversGlaive:IsCastable() then
    if Cast(S.ReaversGlaive, Settings.CommonsOGCD.OffGCDasOffGCD.ReaversGlaive, nil, not Target:IsInRange(50)) then return "reavers_glaive"; end
  end

  if S.SpiritBomb:IsReady() and ((EnemiesCount8yMelee == 1 and SoulFragments >= 5 and false) or (EnemiesCount8yMelee > 1 and (SoulFragments >= 4 or SoulFragments >=3 and Player:BuffUp(S.MetamorphosisBuff)))) then
    if Cast(S.SpiritBomb, nil, nil, not Target:IsInMeleeRange(8)) then return "spirit_bomb simplified 18 Enemy: " .. EnemiesCount8yMelee .. "Souls: " .. SoulFragments; end
  end
  if S.SpiritBurst:IsReady() and ((EnemiesCount8yMelee == 1 and SoulFragments >= 5 and false) or (EnemiesCount8yMelee > 1 and (SoulFragments >= 4 or SoulFragments >=3 and Player:BuffUp(S.MetamorphosisBuff)))) then
    if Cast(S.SpiritBurst, nil, nil, not Target:IsInMeleeRange(8)) then return "spirit_burst simplified 18 Enemy: " .. EnemiesCount8yMelee .. "Souls: " .. SoulFragments; end
  end

  if S.SigilofDoom:IsCastable() and Target:DebuffRefreshable(S.SigilofDoomDebuff) then
    if S.SigilofDoom:Charges() > 1 then
      if Cast(S.SigilofDoom, nil,nil, not Target:IsInRange(30)) then return "sigil_of_flame simplified 28 (Normal)"; end
    else
      if Cast(S.SigilofDoom, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame simplified 28 (Normal)"; end
    end
  end

  if S.SigilofFlame:IsCastable() and Target:DebuffRefreshable(S.SigilofFlameDebuff) then
    if S.SigilofFlame:Charges() > 1 then
      if Cast(S.SigilofFlame, nil,nil, not Target:IsInRange(30)) then return "sigil_of_flame simplified 28 (Normal)"; end
    else
      if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame simplified 28 (Normal)"; end
    end
  end

  if S.ConsumingFire:IsCastable() then
    if Cast(S.ConsumingFire) then return "consuming_fire simplified 22"; end
  end

  if S.ImmolationAura:IsCastable() then
    if Cast(S.ImmolationAura) then return "immolation_aura simplified 22"; end
  end

  if S.Felblade:IsCastable() and (Player:FuryDeficit() > 30) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade"; end
  end

  if S.Fracture:IsCastable() and (((EnemiesCount8yMelee == 1 or Player:HeroTreeID() == 35) and Player:FuryDeficit() >= VarFractureFuryGain) or (EnemiesCount8yMelee > 1 and (SoulFragments <= 2 or SoulFragments <= 3 and not Player:BuffUp(S.MetamorphosisBuff) or SoulFragments > 0 and Player:Fury() < 40))) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture simplified 26"; end
  end

  if S.SoulCleave:IsReady() and (EnemiesCount8yMelee == 1 or Player:HeroTreeID() == 35 or SoulFragments == 0) then
    if Cast(S.SoulCleave, nil, nil, not Target:IsSpellInRange(S.SoulCleave)) then return "soul_cleave simplified 20"; end
  end
  if S.SoulSunder:IsReady() and (EnemiesCount8yMelee == 1 or SoulFragments == 0) then
    if Cast(S.SoulSunder, nil, nil, not Target:IsSpellInRange(S.SoulSunder)) then return "soul_sunder simplified 20"; end
  end

  if CastAnnotated(S.Pool, false, "WAIT") then return "Wait/Pool Resources simplified"; end
end

-- Note: Included because it's in the APL, but we don't handle externals.
--[[local function Externals()
  -- invoke_external_buff,name=symbol_of_hope
  -- invoke_external_buff,name=power_infusion
end]]

local function RGOverflow()
  -- variable,name=trigger_overflow,op=set,value=1
  VarTriggerOverflow = true
  -- variable,name=rg_enhance_cleave,op=set,value=1
  VarRGEnhCleave = true
  -- reavers_glaive,if=(variable.rg_enhance_cleave&fury>=5|!variable.rg_enhance_cleave&fury>=30)&!buff.rending_strike.up&!buff.glaive_flurry.up
  if S.ReaversGlaive:IsCastable() and ((VarRGEnhCleave and Player:Fury() >= 5 or not VarRGEnhCleave and Player:Fury() >= 30) and Player:BuffDown(S.RendingStrikeBuff) and Player:BuffDown(S.GlaiveFlurryBuff)) then
    if Cast(S.ReaversGlaive, Settings.CommonsOGCD.OffGCDasOffGCD.ReaversGlaive, nil, not Target:IsInRange(50)) then return "reavers_glaive rg_overflow 2"; end
  end
end

local function RGSequenceFiller()
  -- felblade,if=fury.deficit>30
  if S.Felblade:IsCastable() and (Player:FuryDeficit() > 30) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade rg_sequence_filler 2"; end
  end
  -- fracture,if=!buff.rending_strike.up
  if S.Fracture:IsCastable() and (Player:BuffDown(S.RendingStrikeBuff)) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture rg_sequence_filler 6"; end
  end
  -- wait,sec=0.1,if=action.fracture.charges_fractional<0.8&(variable.rg_enhance_cleave&buff.rending_strike.up&buff.glaive_flurry.up|!variable.rg_enhance_cleave&!buff.glaive_flurry.up)
  -- sigil_of_flame
  if S.SigilofFlame:IsCastable() then
    if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame rg_sequence_filler 4"; end
  end
  -- sigil_of_spite
  if S.SigilofSpite:IsCastable() then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite rg_sequence_filler 6"; end
  end
  -- soul_carver
  if S.SoulCarver:IsCastable() then
    if Cast(S.SoulCarver, nil, nil, not IsInMeleeRange) then return "soul_carver rg_sequence_filler 8"; end
  end
  -- fel_devastation
  if S.FelDevastation:IsReady() then
    if Cast(S.FelDevastation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_devastation rg_sequence_filler 10"; end
  end
  -- throw_glaive
  if S.ThrowGlaive:IsCastable() then
    if Cast(S.ThrowGlaive, nil, nil, not Target:IsSpellInRange(S.ThrowGlaive)) then return "throw_glaive rg_sequence_filler 12"; end
  end
end

local function RGSequence()
  -- call_action_list,name=rg_sequence_filler,if=(fury<30&(!variable.rg_enhance_cleave&buff.glaive_flurry.up&buff.rending_strike.up|variable.rg_enhance_cleave&!buff.rending_strike.up))|(action.fracture.charges_fractional<1&(variable.rg_enhance_cleave&buff.rending_strike.up&buff.glaive_flurry.up|!variable.rg_enhance_cleave&!buff.glaive_flurry.up))
  if (Player:Fury() < 30 and (not VarRGEnhCleave and Player:BuffUp(S.GlaiveFlurryBuff) and Player:BuffUp(S.RendingStrikeBuff) or VarRGEnhCleave and Player:BuffDown(S.RendingStrikeBuff))) or (S.Fracture:ChargesFractional() < 1 and (VarRGEnhCleave and Player:BuffUp(S.RendingStrikeBuff) and Player:BuffUp(S.GlaiveFlurryBuff) or not VarRGEnhCleave and Player:BuffDown(S.GlaiveFlurryBuff))) then
    local ShouldReturn = RGSequenceFiller(); if ShouldReturn then return ShouldReturn; end
  end
  -- fracture,if=(variable.rg_enhance_cleave&buff.rending_strike.up&buff.glaive_flurry.up|!variable.rg_enhance_cleave&!buff.glaive_flurry.up)
  if S.Fracture:IsCastable() and (VarRGEnhCleave and Player:BuffUp(S.RendingStrikeBuff) and Player:BuffUp(S.GlaiveFlurryBuff) or not VarRGEnhCleave and Player:BuffDown(S.GlaiveFlurryBuff)) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture rg_sequence 2"; end
  end
  -- shear,if=(variable.rg_enhance_cleave&buff.rending_strike.up&buff.glaive_flurry.up|!variable.rg_enhance_cleave&!buff.glaive_flurry.up)
  if S.Shear:IsCastable() and (VarRGEnhCleave and Player:BuffUp(S.RendingStrikeBuff) and Player:BuffUp(S.GlaiveFlurryBuff) or not VarRGEnhCleave and Player:BuffDown(S.GlaiveFlurryBuff)) then
    if Cast(S.Shear, nil, nil, not IsInMeleeRange) then return "shear rg_sequence 4"; end
  end
  -- soul_cleave,if=(!variable.rg_enhance_cleave&buff.glaive_flurry.up&buff.rending_strike.up|variable.rg_enhance_cleave&!buff.rending_strike.up)
  if S.SoulCleave:IsReady() and (not VarRGEnhCleave and Player:BuffUp(S.GlaiveFlurryBuff) and Player:BuffUp(S.RendingStrikeBuff) or VarRGEnhCleave and Player:BuffDown(S.RendingStrikeBuff)) then
    if Cast(S.SoulCleave, nil, nil, not Target:IsInMeleeRange(8)) then return "soul_cleave rg_sequence 6"; end
  end
end

local function ARExecute()
  -- metamorphosis,use_off_gcd=1
  if S.Metamorphosis:IsCastable() then
    if Cast(S.Metamorphosis, nil, Settings.CommonsDS.DisplayStyle.Metamorphosis) then return "metamorphosis ar_execute 2"; end
  end
  -- reavers_glaive,if=fury>=30
  if S.ReaversGlaive:IsCastable() and (Player:Fury() >= 30) then
    if Cast(S.ReaversGlaive, Settings.CommonsOGCD.OffGCDasOffGCD.ReaversGlaive, nil, not Target:IsInRange(50)) then return "reavers_glaive ar_execute 4"; end
  end
  -- the_hunt,if=!buff.reavers_glaive.up
  if S.TheHunt:IsCastable() and (Player:BuffDown(S.ReaversGlaiveBuff)) then
    if Cast(S.TheHunt, nil, Settings.CommonsDS.DisplayStyle.TheHunt, not Target:IsInRange(50)) then return "the_hunt ar_execute 6"; end
  end
  -- bulk_extraction,if=spell_targets>=3&buff.art_of_the_glaive.stack>=20
  if S.BulkExtraction:IsCastable() and (EnemiesCount8yMelee >= 3 and Player:BuffStack(S.ArtoftheGlaiveBuff) >= 20) then
    if Cast(S.BulkExtraction, Settings.Vengeance.OffGCDasOffGCD.BulkExtraction, nil, not Target:IsInMeleeRange(8)) then return "bulk_extraction ar_execute 8"; end
  end
  -- sigil_of_flame
  if S.SigilofFlame:IsCastable() then
    if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame ar_execute 10"; end
  end
  -- fiery_brand
  if S.FieryBrand:IsCastable() then
    if Cast(S.FieryBrand, nil, Settings.Vengeance.DisplayStyle.FieryBrand, not Target:IsSpellInRange(S.FieryBrand)) then return "fiery_brand ar_execute 12"; end
  end
  -- sigil_of_spite
  if S.SigilofSpite:IsCastable() then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite ar_execute 14"; end
  end
  -- soul_carver
  if S.SoulCarver:IsCastable() then
    if Cast(S.SoulCarver, nil, nil, not IsInMeleeRange) then return "soul_carver ar_execute 16"; end
  end
  -- fel_devastation
  if S.FelDevastation:IsReady() then
    if Cast(S.FelDevastation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_devastation ar_execute 18"; end
  end
end

local function AR()
  -- variable,name=spb_threshold,op=setif,condition=talent.fiery_demise&dot.fiery_brand.ticking,value=(variable.single_target*5)+(variable.small_aoe*4)+(variable.big_aoe*4),value_else=(variable.single_target*5)+(variable.small_aoe*5)+(variable.big_aoe*4)
  -- Note: Currently the value and value_else are identical, so skipping the condition check.
  if S.FieryDemise:IsAvailable() and S.FieryBrandDebuff:AuraActiveCount() > 0 then
    VarSpBThreshold = (num(VarST) * 5) + (num(VarSmallAoE) * 4) + (num(VarBigAoE) * 4)
  else
    VarSpBThreshold = (num(VarST) * 5) + (num(VarSmallAoE) * 5) + (num(VarBigAoE) * 4)
  end
  -- variable,name=can_spb,op=setif,condition=talent.spirit_bomb,value=soul_fragments>=variable.spb_threshold,value_else=0
  VarCanSpB = S.SpiritBomb:IsAvailable() and SoulFragments >= VarSpBThreshold
  -- variable,name=can_spb_soon,op=setif,condition=talent.spirit_bomb,value=soul_fragments.total>=variable.spb_threshold,value_else=0
  VarCanSpBSoon = S.SpiritBomb:IsAvailable() and TotalSoulFragments >= VarSpBThreshold
  -- variable,name=can_spb_one_gcd,op=setif,condition=talent.spirit_bomb,value=(soul_fragments.total+variable.num_spawnable_souls)>=variable.spb_threshold,value_else=0
  VarCanSpBOneGCD = S.SpiritBomb:IsAvailable() and (TotalSoulFragments + VarNumSpawnableSouls) >= VarSpBThreshold
  -- variable,name=dont_soul_cleave,value=talent.spirit_bomb&((variable.can_spb|variable.can_spb_soon|variable.can_spb_one_gcd)|prev_gcd.1.fracture)
  VarDontSoulCleave = S.SpiritBomb:IsAvailable() and ((VarCanSpB or VarCanSpBSoon or VarCanSpBOneGCD) or Player:PrevGCD(1, S.Fracture))
  -- variable,name=double_rm_expires,op=set,value=time+20,if=prev_gcd.1.fracture&debuff.reavers_mark.stack=2&debuff.reavers_mark.remains>(20-gcd.max)&!buff.rending_strike.up&!buff.glaive_flurry.up
  VarDoubleRMExpires = 0
  if Player:PrevGCD(1, S.Fracture) and Target:DebuffStack(S.ReaversMarkDebuff) == 2 and Target:DebuffRemains(S.ReaversMarkDebuff) > (20 - Player:GCD()) and Player:BuffDown(S.RendingStrikeBuff) and Player:BuffDown(S.GlaiveFlurryBuff) then
    VarDoubleRMExpires = HL.CombatTime() + 20
  end
  -- variable,name=double_rm_remains,op=setif,condition=(variable.double_rm_expires-time)>0,value=variable.double_rm_expires-time,value_else=0
  VarDoubleRMRemains = ((VarDoubleRMExpires - HL.CombatTime()) > 0) and (VarDoubleRMExpires - HL.CombatTime()) or 0
  -- variable,name=rg_sequence_duration,op=set,value=action.fracture.execute_time+action.soul_cleave.execute_time+action.reavers_glaive.execute_time
  VarRGSequenceDuration = S.Fracture:ExecuteTime() + S.SoulCleave:ExecuteTime() + S.ReaversGlaive:ExecuteTime()
  -- variable,name=rg_sequence_duration,op=add,value=gcd.max,if=!talent.keen_engagement
  VarRGSequenceDuration = (not S.KeenEngagement:IsAvailable()) and VarRGSequenceDuration + Player:GCD() or VarRGSequenceDuration
  -- variable,name=trigger_overflow,op=set,value=0,if=!buff.glaive_flurry.up&!buff.rending_strike.up
  if Player:BuffDown(S.GlaiveFlurryBuff) and Player:BuffDown(S.RendingStrikeBuff) then
    VarTriggerOverflow = false
  end
  -- variable,name=rg_enhance_cleave,op=setif,condition=spell_targets.spirit_bomb>4|fight_remains<8|variable.trigger_overflow,value=1,value_else=0
  VarRGEnhCleave = (EnemiesCount8yMelee > 4 or BossFightRemains < 8 or VarTriggerOverflow)
  -- variable,name=cooldown_sync,value=(debuff.reavers_mark.remains>gcd.max&debuff.reavers_mark.stack=2&buff.thrill_of_the_fight_damage.remains>gcd.max)|fight_remains<20
  VarCDSync = (Target:DebuffRemains(S.ReaversMarkDebuff) > Player:GCD() and Target:DebuffStack(S.ReaversMarkDebuff) == 2 and Player:BuffRemains(S.ThrilloftheFightDmgBuff) > Player:GCD()) or BossFightRemains < 20
  -- potion,use_off_gcd=1,if=gcd.remains=0&(variable.cooldown_sync|(buff.rending_strike.up&buff.glaive_flurry.up))
  if Settings.Commons.Enabled.Potions and (VarCDSync or (Player:BuffUp(S.RendingStrikeBuff) and Player:BuffUp(S.GlaiveFlurryBuff))) then
    local PotionSelected = Everyone.PotionSelected()
    if PotionSelected and PotionSelected:IsReady() then
      if Cast(PotionSelected, nil, Settings.CommonsDS.DisplayStyle.Potions) then return "potion ar 2"; end
    end
  end
  -- use_items,use_off_gcd=1,if=variable.cooldown_sync
  if (Settings.Commons.Enabled.Trinkets or Settings.Commons.Enabled.Items) and VarCDSync then
    local ItemToUse, ItemSlot, ItemRange = Player:GetUseableItems(OnUseExcludes)
    if ItemToUse then
      local DisplayStyle = Settings.CommonsDS.DisplayStyle.Trinkets
      if ItemSlot ~= 13 and ItemSlot ~= 14 then DisplayStyle = Settings.CommonsDS.DisplayStyle.Items end
      if ((ItemSlot == 13 or (ItemSlot == 14 and false)) and Settings.Commons.Enabled.Trinkets) or (ItemSlot ~= 13 and ItemSlot ~= 14 and Settings.Commons.Enabled.Items) then
        if Cast(ItemToUse, nil, DisplayStyle, not Target:IsInRange(ItemRange)) then return "Generic use_items for " .. ItemToUse:Name(); end
      end
    end
  end

  if (Settings.Vengeance.UseSimplifiedRotation) then
    return SimplifiedAPL()
  end

  -- call_action_list,name=externals,if=variable.cooldown_sync
  -- Note: Not handling externals.
  -- run_action_list,name=rg_sequence,if=buff.glaive_flurry.up|buff.rending_strike.up
  -- Note: Added FuryoftheAldrachi check to avoid stalling the profile if it's not yet learned.
  if S.FuryoftheAldrachi:IsAvailable() and (Player:BuffUp(S.GlaiveFlurryBuff) or Player:BuffUp(S.RendingStrikeBuff)) then
    local ShouldReturn = RGSequence(); if ShouldReturn then return ShouldReturn; end
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for RGSequence()"; end
  end
  -- metamorphosis,use_off_gcd=1,if=!buff.metamorphosis.up&gcd.remains=0&cooldown.the_hunt.remains>5&!(buff.rending_strike.up&buff.glaive_flurry.up)
  if S.Metamorphosis:IsCastable() and (Player:BuffDown(S.MetamorphosisBuff) and S.TheHunt:CooldownRemains() > 5 and not (Player:BuffUp(S.RendingStrikeBuff) and Player:BuffUp(S.GlaiveFlurryBuff))) then
    if Cast(S.Metamorphosis, nil, Settings.CommonsDS.DisplayStyle.Metamorphosis) then return "metamorphosis ar 4"; end
  end
  -- vengeful_retreat,use_off_gcd=1,if=talent.unhindered_assault&!cooldown.felblade.up&(((talent.spirit_bomb&(fury<40&(variable.can_spb|variable.can_spb_soon)))|(talent.spirit_bomb&(cooldown.sigil_of_spite.remains<gcd.max|cooldown.soul_carver.remains<gcd.max)&(cooldown.fel_devastation.remains<(gcd.max*2))&fury<50))|(fury<30&(soul_fragments<=2|cooldown.fracture.charges_fractional<1)))
  if S.VengefulRetreat:IsCastable() and (S.UnhinderedAssault:IsAvailable() and S.Felblade:CooldownDown() and (((S.SpiritBomb:IsAvailable() and (Player:Fury() < 40 and (VarCanSpB or VarCanSpBSoon))) or (S.SpiritBomb:IsAvailable() and (S.SigilofSpite:CooldownRemains() < Player:GCD() or S.SoulCarver:CooldownRemains() < Player:GCD()) and (S.FelDevastation:CooldownRemains() < (Player:GCD() * 2)) and Player:Fury() < 50)) or (Player:Fury() < 30 and (SoulFragments <= 2 or S.Fracture:ChargesFractional() < 1)))) then
    if Cast(S.VengefulRetreat, Settings.Vengeance.OffGCDasOffGCD.VengefulRetreat) then return "vengeful_retreat ar 6"; end
  end
  -- the_hunt,if=!buff.reavers_glaive.up&(buff.art_of_the_glaive.stack+soul_fragments.total)<20
  if S.TheHunt:IsCastable() and (Player:BuffDown(S.ReaversGlaiveBuff) and (Player:BuffStack(S.ArtoftheGlaiveBuff) + TotalSoulFragments) < 20) then
    if Cast(S.TheHunt, nil, Settings.CommonsDS.DisplayStyle.TheHunt, not Target:IsInRange(50)) then return "the_hunt ar 8"; end
  end
  -- immolation_aura,if=!(buff.glaive_flurry.up|buff.rending_strike.up)
  if ImmoAbility:IsCastable() and (not (Player:BuffUp(S.GlaiveFlurryBuff) or Player:BuffUp(S.RendingStrikeBuff))) then
    if Cast(ImmoAbility) then return "immolation_aura ar 10"; end
  end
  -- sigil_of_flame,if=!(buff.glaive_flurry.up|buff.rending_strike.up)&(talent.ascending_flame|(!talent.ascending_flame&!prev_gcd.1.sigil_of_flame&(dot.sigil_of_flame.remains<(1+talent.quickened_sigils))))
  if S.SigilofFlame:IsCastable() and (not (Player:BuffUp(S.GlaiveFlurryBuff) or Player:BuffUp(S.RendingStrikeBuff)) and (S.AscendingFlame:IsAvailable() or (not S.AscendingFlame:IsAvailable() and not Player:PrevGCD(1, S.SigilofFlame) and (Target:DebuffRemains(S.SigilofFlameDebuff) < (1 + num(S.QuickenedSigils:IsAvailable())))))) then
    if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame ar 12"; end
  end
  -- call_action_list,name=rg_overflow,if=buff.reavers_glaive.up&buff.thrill_of_the_fight_damage.up&buff.thrill_of_the_fight_damage.remains<variable.rg_sequence_duration&(((((1.2*(1+raw_haste_pct))*(variable.double_rm_remains-variable.rg_sequence_duration))+soul_fragments.total+buff.art_of_the_glaive.stack)>=20)|((cooldown.the_hunt.remains)<(variable.double_rm_remains-(variable.rg_sequence_duration+action.the_hunt.execute_time))))
  if Player:BuffUp(S.ReaversGlaiveBuff) and Player:BuffUp(S.ThrilloftheFightDmgBuff) and Player:BuffRemains(S.ThrilloftheFightDmgBuff) < VarRGSequenceDuration and (((((1.2 * (1 + Player:HastePct())) * (VarDoubleRMRemains - VarRGSequenceDuration)) + TotalSoulFragments + Player:BuffStack(S.ArtoftheGlaiveBuff)) >= 20) or ((S.TheHunt:CooldownRemains()) < (VarDoubleRMRemains - (VarRGSequenceDuration + S.TheHunt:ExecuteTime())))) then
    local ShouldReturn = RGOverflow(); if ShouldReturn then return ShouldReturn; end
  end
  -- call_action_list,name=ar_execute,if=fight_remains<20
  if BossFightRemains < 20 then
    local ShouldReturn = ARExecute(); if ShouldReturn then return ShouldReturn; end
  end
  -- soul_cleave,if=(variable.double_rm_remains<=(execute_time+variable.rg_sequence_duration))&(soul_fragments.total>=2&buff.art_of_the_glaive.stack>=(20-2))&(fury<40|!variable.can_spb)
  if S.SoulCleave:IsReady() and ((VarDoubleRMRemains <= (Player:GCDRemains() + S.SoulCleave:ExecuteTime() + VarRGSequenceDuration)) and (TotalSoulFragments >= 2 and Player:BuffStack(S.ArtoftheGlaiveBuff) >= (18)) and (Player:Fury() < 40 or not VarCanSpB)) then
    if Cast(S.SoulCleave, nil, nil, not IsInMeleeRange) then return "soul_cleave ar 14"; end
  end
  -- spirit_bomb,if=(variable.double_rm_remains<=(execute_time+variable.rg_sequence_duration))&(buff.art_of_the_glaive.stack+soul_fragments.total>=20)
  if S.SpiritBomb:IsReady() and ((VarDoubleRMRemains <= (Player:GCDRemains() + S.SpiritBomb:ExecuteTime() + VarRGSequenceDuration)) and (Player:BuffStack(S.ArtoftheGlaiveBuff) + TotalSoulFragments > 20)) then
    if Cast(S.SpiritBomb, nil, nil, not Target:IsInMeleeRange(8)) then return "spirit_bomb ar 16"; end
  end
  -- bulk_extraction,if=(variable.double_rm_remains<=(execute_time+variable.rg_sequence_duration))&(buff.art_of_the_glaive.stack+(spell_targets>?5)>=20)
  if S.BulkExtraction:IsCastable() and ((VarDoubleRMRemains <= (Player:GCDRemains() + S.BulkExtraction:ExecuteTime() + VarRGSequenceDuration)) and (Player:BuffStack(S.ArtoftheGlaiveBuff) + mathmin(EnemiesCount8yMelee, 5) >= 20)) then
    if Cast(S.BulkExtraction, Settings.Vengeance.OffGCDasOffGCD.BulkExtraction, nil, not Target:IsInMeleeRange(8)) then return "bulk_extraction ar 18"; end
  end
  -- reavers_glaive,if=(variable.rg_enhance_cleave&fury>=5|!variable.rg_enhance_cleave&fury>=30)&buff.thrill_of_the_fight_damage.remains<variable.rg_sequence_duration&(!buff.thrill_of_the_fight_attack_speed.up|(variable.double_rm_remains<=variable.rg_sequence_duration)|variable.rg_enhance_cleave)
  if S.ReaversGlaive:IsCastable() and ((VarRGEnhCleave and Player:Fury() >= 5 or not VarRGEnhCleave and Player:Fury() >= 30) and Player:BuffRemains(S.ThrilloftheFightDmgBuff) < VarRGSequenceDuration and (Player:BuffDown(S.ThrilloftheFightAtkBuff) or (VarDoubleRMRemains <= VarRGSequenceDuration) or VarRGEnhCleave)) then
    if Cast(S.ReaversGlaive, Settings.CommonsOGCD.OffGCDasOffGCD.ReaversGlaive, nil, not Target:IsInRange(50)) then return "reavers_glaive ar 20"; end
  end
  -- fiery_brand,if=!talent.fiery_demise|(talent.fiery_demise&((talent.down_in_flames&charges>=max_charges)|(active_dot.fiery_brand=0)))
  if S.FieryBrand:IsCastable() and (not S.FieryDemise:IsAvailable() or (S.FieryDemise:IsAvailable() and ((S.DowninFlames:IsAvailable() and S.FieryBrand:Charges() >= S.FieryBrand:MaxCharges()) or (S.FieryBrandDebuff:AuraActiveCount() == 0)))) then
    if Cast(S.FieryBrand, nil, Settings.Vengeance.DisplayStyle.FieryBrand, not Target:IsSpellInRange(S.FieryBrand)) then return "fiery_brand ar 22"; end
  end
  -- sigil_of_spite,if=!talent.spirit_bomb|(talent.spirit_bomb&fury>=40&(variable.can_spb|variable.can_spb_soon|soul_fragments.total<=(2-talent.soul_sigils.rank)))
  if S.SigilofSpite:IsCastable() and (not S.SpiritBomb:IsAvailable() or (S.SpiritBomb:IsAvailable() and Player:Fury() >= 40 and (VarCanSpB or VarCanSpBSoon or SoulFragments <= (2 - S.SoulSigils:TalentRank())))) then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite ar 24"; end
  end
  -- Manually added: wait,if=!variable.can_spb&soul_fragments.total>=variable.spb_threshold
  if not VarCanSpB and TotalSoulFragments >= VarSpBThreshold and SoulFragments < 5 then
    if CastAnnotated(S.Pool, false, "WAIT") then return "Wait for Soul Fragments"; end
  end
  -- spirit_bomb,if=variable.can_spb
  if S.SpiritBomb:IsReady() and (VarCanSpB) then
    if Cast(S.SpiritBomb, nil, nil, not Target:IsInMeleeRange(8)) then return "spirit_bomb ar 26"; end
  end
  -- fel_devastation,if=talent.spirit_bomb&!variable.can_spb&(variable.can_spb_soon|soul_fragments.inactive>=1|prev_gcd.1.sigil_of_spite|prev_gcd.1.soul_carver)
  if S.FelDevastation:IsReady() and (S.SpiritBomb:IsAvailable() and not VarCanSpB and (VarCanSpBSoon or IncSoulFragments >= 1 or Player:PrevGCD(1, S.SigilofSpite) or Player:PrevGCD(2, S.SoulCarver))) then
    if Cast(S.FelDevastation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_devastation ar 28"; end
  end
  -- soul_carver,if=!talent.spirit_bomb|((soul_fragments.total+3)<=5)
  if S.SoulCarver:IsCastable() and (not S.SpiritBomb:IsAvailable() or ((TotalSoulFragments + 3) <= 5)) then
    if Cast(S.SoulCarver, nil, nil, not IsInMeleeRange) then return "soul_carver ar 30"; end
  end
  -- soul_cleave,if=fury.deficit<25
  if S.SoulCleave:IsReady() and (Player:FuryDeficit() < 25) then
    if Cast(S.SoulCleave, nil, nil, not IsInMeleeRange) then return "soul_cleave ar 32"; end
  end
  -- fracture,if=talent.spirit_bomb&(variable.can_spb|variable.can_spb_soon|variable.can_spb_one_gcd)&fury<40&!cooldown.felblade.up&(!talent.unhindered_assault|(talent.unhindered_assault&!cooldown.vengeful_retreat.up))
  if S.Fracture:IsCastable() and (S.SpiritBomb:IsAvailable() and (VarCanSpB or VarCanSpBSoon or VarCanSpBOneGCD) and Player:Fury() < 40 and S.Felblade:CooldownDown() and (not S.UnhinderedAssault:IsAvailable() or (S.UnhinderedAssault:IsAvailable() and S.VengefulRetreat:CooldownDown()))) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture ar 34"; end
  end
  -- fel_devastation,if=!variable.single_target|buff.thrill_of_the_fight_damage.up
  if S.FelDevastation:IsReady() and (not VarST or Player:BuffUp(S.ThrilloftheFightDmgBuff)) then
    if Cast(S.FelDevastation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_devastation ar 36"; end
  end
  -- bulk_extraction,if=spell_targets>=5
  if S.BulkExtraction:IsCastable() and (EnemiesCount8yMelee >= 5) then
    if Cast(S.BulkExtraction, Settings.Vengeance.OffGCDasOffGCD.BulkExtraction, nil, not Target:IsInMeleeRange(8)) then return "bulk_extraction ar 38"; end
  end
  -- felblade,if=(((talent.spirit_bomb&(fury<40&(variable.can_spb|variable.can_spb_soon)))|(talent.spirit_bomb&(cooldown.sigil_of_spite.remains<gcd.max|cooldown.soul_carver.remains<gcd.max)&(cooldown.fel_devastation.remains<(gcd.max*2))&fury<50))|(fury<30&(soul_fragments<=2|cooldown.fracture.charges_fractional<1)))
  if S.Felblade:IsCastable() and (((S.SpiritBomb:IsAvailable() and (Player:Fury() < 40 and (VarCanSpB or VarCanSpBSoon))) or (S.SpiritBomb:IsAvailable() and (S.SigilofSpite:CooldownRemains() < Player:GCD() or S.SoulCarver:CooldownRemains() < Player:GCD()) and (S.FelDevastation:CooldownRemains() < (Player:GCD() * 2)) and Player:Fury() < 50)) and (Player:Fury() < 30 and (SoulFragments <= 2 or S.Fracture:ChargesFractional() < 1))) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade ar 40"; end
  end
  -- soul_cleave,if=fury.deficit<=25|(!talent.spirit_bomb|!variable.dont_soul_cleave)
  if S.SoulCleave:IsReady() and (Player:FuryDeficit() <= 25 or (not S.SpiritBomb:IsAvailable() or not VarDontSoulCleave)) then
    if Cast(S.SoulCleave, nil, nil, not IsInMeleeRange) then return "soul_cleave ar 42"; end
  end
  -- fracture
  if S.Fracture:IsCastable() then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture ar 44"; end
  end
  -- shear
  if S.Shear:IsCastable() then
    if Cast(S.Shear, nil, nil, not IsInMeleeRange) then return "shear ar 46"; end
  end
  -- felblade
  if S.Felblade:IsCastable() then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade ar 48"; end
  end
  -- throw_glaive
  if S.ThrowGlaive:IsCastable() then
    if Cast(S.ThrowGlaive, nil, nil, not Target:IsSpellInRange(S.ThrowGlaive)) then return "throw_glaive ar 50"; end
  end
end

local function FelDev()
  -- spirit_burst,if=buff.demonsurge_spirit_burst.up&(variable.can_spburst|soul_fragments>=4|(buff.metamorphosis.remains<(gcd.max*2)))
  if S.SpiritBurst:IsReady() and (Player:Demonsurge("SpiritBurst") and (VarCanSpBurst or SoulFragments >= 4 or Player:BuffRemains(S.MetamorphosisBuff) < (Player:GCD() * 2))) then
    if Cast(S.SpiritBurst, nil, nil, not IsInAoERange) then return "spirit_burst fel_dev 2"; end
  end
  -- soul_sunder,if=buff.demonsurge_soul_sunder.up&(!buff.demonsurge_spirit_burst.up|(buff.metamorphosis.remains<(gcd.max*2)))
  if S.SoulSunder:IsReady() and (Player:Demonsurge("SoulSunder") and (not Player:Demonsurge("SpiritBurst") or Player:BuffRemains(S.MetamorphosisBuff) < (Player:GCD() * 2))) then
    if Cast(S.SoulSunder, nil, nil, not IsInMeleeRange) then return "soul_sunder fel_dev 4"; end
  end
  -- sigil_of_spite,if=soul_fragments.total<=2&buff.demonsurge_spirit_burst.up
  if S.SigilofSpite:IsCastable() and (TotalSoulFragments <= 2 and Player:Demonsurge("SpiritBurst")) then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite fel_dev 6"; end
  end
  -- soul_carver,if=soul_fragments.total<=2&!prev_gcd.1.sigil_of_spite&buff.demonsurge_spirit_burst.up
  if S.SoulCarver:IsCastable() and (TotalSoulFragments <= 2 and not Player:PrevGCD(1, S.SigilofSpite) and Player:Demonsurge("SpiritBurst")) then
    if Cast(S.SoulCarver, nil, nil, not IsInMeleeRange) then return "soul_carver fel_dev 8"; end
  end
  -- fracture,if=soul_fragments.total<=2&buff.demonsurge_spirit_burst.up
  if S.Fracture:IsCastable() and (TotalSoulFragments <= 2 and Player:Demonsurge("SpiritBurst")) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture fel_dev 10"; end
  end
  -- felblade,if=buff.demonsurge_spirit_burst.up|buff.demonsurge_soul_sunder.up
  if S.Felblade:IsCastable() and (Player:Demonsurge("SpiritBurst") or Player:Demonsurge("SoulSunder")) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade fel_dev 12"; end
  end
  -- fracture,if=buff.demonsurge_spirit_burst.up|buff.demonsurge_soul_sunder.up
  if S.Fracture:IsCastable() and (Player:Demonsurge("SpiritBurst") or Player:Demonsurge("SoulSunder")) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture fel_dev 14"; end
  end
  -- Manually added: shear
  if S.Shear:IsCastable() and (Player:Demonsurge("SpiritBurst") or Player:Demonsurge("SoulSunder"))then
    if Cast(S.Shear, nil, nil, not IsInMeleeRange) then return "shear fel_dev 16"; end
  end
end

local function FelDevPrep()
  -- potion,use_off_gcd=1,if=prev_gcd.1.fiery_brand
  if Settings.Commons.Enabled.Potions and Player:PrevGCD(1, S.FieryBrand) then
    local PotionSelected = Everyone.PotionSelected()
    if PotionSelected and PotionSelected:IsReady() then
      if Cast(PotionSelected, nil, Settings.CommonsDS.DisplayStyle.Potions) then return "potion fel_dev_prep 2"; end
    end
  end
  -- sigil_of_flame,if=!variable.hold_sof_for_precombat&!variable.hold_sof_for_student&!variable.hold_sof_for_dot
  if S.SigilofFlame:IsCastable() and (not VarHoldSoFForPrecombat and not VarHoldSoFForStudent and not VarHoldSoFForDot) then
    if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame fs 4"; end
  end
  -- fiery_brand,if=talent.fiery_demise&((fury+variable.fel_dev_passive_fury_gen)>=120)&(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4)&active_dot.fiery_brand=0&((cooldown.metamorphosis.remains<(execute_time+action.fel_devastation.execute_time+(gcd.max*2)))|variable.fiery_brand_back_before_meta)
  if S.FieryBrand:IsCastable() and (S.FieryDemise:IsAvailable() and ((Player:Fury() + VarFelDevPassiveFuryGen) >= 120) and (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments >= 4) and S.FieryBrandDebuff:AuraActiveCount() == 0 and ((S.Metamorphosis:CooldownRemains() < (S.FieryBrand:ExecuteTime() + S.FelDevastation:ExecuteTime() + (Player:GCD() * 2))) or VarFBBeforeMeta)) then
    if Cast(S.FieryBrand, nil, Settings.Vengeance.DisplayStyle.FieryBrand, not Target:IsSpellInRange(S.FieryBrand)) then return "fiery_brand fel_dev_prep 4"; end
  end
  -- fel_devastation,if=((fury+variable.fel_dev_passive_fury_gen)>=120)&(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4)
  if S.FelDevastation:IsReady() and (((Player:Fury() + VarFelDevPassiveFuryGen) >= 120) and (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments >= 4)) then
    if Cast(S.FelDevastation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_devastation fel_dev_prep 6"; end
  end
  -- sigil_of_spite,if=(!talent.cycle_of_binding|cooldown.metamorphosis.remains>20)&(soul_fragments.total<=1|(!(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4)&action.fracture.charges_fractional<1))
  if S.SigilofSpite:IsCastable() and (not S.CycleofBinding:IsAvailable() or S.Metamorphosis:CooldownRemains() > 20) and (TotalSoulFragments <= 1 or (not (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments >= 4) and S.Fracture:ChargesFractional() < 1)) then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite fel_dev_prep 8"; end
  end
  -- soul_carver,if=(!talent.cycle_of_binding|cooldown.metamorphosis.remains>20)&(soul_fragments.total<=1|(!(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4)&action.fracture.charges_fractional<1))&!prev_gcd.1.sigil_of_spite&!prev_gcd.2.sigil_of_spite
  if S.SoulCarver:IsCastable() and (not S.CycleofBinding:IsAvailable() or S.Metamorphosis:CooldownRemains() > 20) and ((TotalSoulFragments <= 1 or (not (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments >= 4) and S.Fracture:ChargesFractional() < 1)) and not Player:PrevGCD(1, S.SigilofSpite) and not Player:PrevGCD(2, S.SigilofSpite)) then
    if Cast(S.SoulCarver, nil, nil, not IsInMeleeRange) then return "soul_carver fel_dev_prep 10"; end
  end
  -- felblade,if=!((fury+variable.fel_dev_passive_fury_gen)>=120)&(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4)
  if S.Felblade:IsCastable() and (not ((Player:Fury() + VarFelDevPassiveFuryGen) >= 120) and (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments >= 4)) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade fel_dev_prep 12"; end
  end
  -- fracture,if=!(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4)|!((fury+variable.fel_dev_passive_fury_gen)>=120)
  if S.Fracture:IsCastable() and (not (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments >= 4) or not ((Player:Fury() + VarFelDevPassiveFuryGen) >= 120)) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture fel_dev_prep 14"; end
  end
  -- felblade
  if S.Felblade:IsCastable() then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade fel_dev_prep 16"; end
  end
  -- fracture
  if S.Fracture:IsCastable() then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture fel_dev_prep 18"; end
  end
  -- wait,sec=0.1,if=(!(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4)|!((fury+variable.fel_dev_passive_fury_gen)>=120))&action.fracture.charges_fractional>=0.7
  -- fel_devastation
  if S.FelDevastation:IsReady() then
    if Cast(S.FelDevastation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_devastation fel_dev_prep 20"; end
  end
  -- soul_cleave,if=((fury+variable.fel_dev_passive_fury_gen)>=150)
  if S.SoulCleave:IsReady() and ((Player:Fury() + VarFelDevPassiveFuryGen) >= 150) then
    if Cast(S.SoulCleave, nil, nil, not IsInMeleeRange) then return "soul_cleave fel_dev_prep 22"; end
  end
  -- throw_glaive
  if S.ThrowGlaive:IsCastable() then
    if Cast(S.ThrowGlaive, nil, nil, not Target:IsSpellInRange(S.ThrowGlaive)) then return "throw_glaive fel_dev_prep 24"; end
  end
  -- Manually added: shear
  if S.Shear:IsCastable() then
    if Cast(S.Shear, nil, nil, not IsInMeleeRange) then return "shear fel_dev_prep 26"; end
  end
end

local function FSExecute()
  -- metamorphosis,use_off_gcd=1
  if S.Metamorphosis:IsCastable() then
    if Cast(S.Metamorphosis, nil, Settings.CommonsDS.DisplayStyle.Metamorphosis) then return "metamorphosis fs_execute 2"; end
  end
  -- the_hunt
  if S.TheHunt:IsCastable() then
    if Cast(S.TheHunt, nil, Settings.CommonsDS.DisplayStyle.TheHunt, not Target:IsInRange(50)) then return "the_hunt fs_execute 4"; end
  end
  -- sigil_of_flame
  if S.SigilofFlame:IsCastable() then
    if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame fs_execute 6"; end
  end
  -- fiery_brand
  if S.FieryBrand:IsCastable() then
    if Cast(S.FieryBrand, nil, Settings.Vengeance.DisplayStyle.FieryBrand, not Target:IsSpellInRange(S.FieryBrand)) then return "fiery_brand fs_execute 8"; end
  end
  -- sigil_of_spite
  if S.SigilofSpite:IsCastable() then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite fs_execute 10"; end
  end
  -- soul_carver
  if S.SoulCarver:IsCastable() then
    if Cast(S.SoulCarver, nil, nil, not IsInMeleeRange) then return "soul_carver fs_execute 12"; end
  end
  -- fel_devastation
  if S.FelDevastation:IsReady() then
    if Cast(S.FelDevastation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_devastation fs_execute 14"; end
  end
end

local function MetaPrep()
  -- Note: metamorphosis and sigil_of_flame moved into a CastQueue.
  -- Note: Intent is to suggest metamorphosis after sigil_of_flame, but before the sigil explodes.
  -- Note: Doing this allows the sigil_of_flame to deal damage as sigil_of_doom.
  -- metamorphosis,use_off_gcd=1,if=cooldown.sigil_of_flame.charges<1
  --if S.Metamorphosis:IsCastable() and (S.SigilofFlame:Charges() < 1) then
    --if Cast(S.Metamorphosis) then return "metamorphosis meta_prep 2"; end
  --end
  -- fiery_brand,if=talent.fiery_demise&((talent.down_in_flames&charges>=max_charges)|active_dot.fiery_brand=0)
  if S.FieryBrand:IsCastable() and (S.FieryDemise:IsAvailable() and ((S.DowninFlames:IsAvailable() and S.FieryBrand:Charges() >= S.FieryBrand:MaxCharges()) or S.FieryBrandDebuff:AuraActiveCount() == 0)) then
    if Cast(S.FieryBrand, nil, Settings.Vengeance.DisplayStyle.FieryBrand, not Target:IsSpellInRange(S.FieryBrand)) then return "fiery_brand meta_prep 2"; end
  end
  -- potion,use_off_gcd=1
  if Settings.Commons.Enabled.Potions then
    local PotionSelected = Everyone.PotionSelected()
    if PotionSelected and PotionSelected:IsReady() then
      if Cast(PotionSelected, nil, Settings.CommonsDS.DisplayStyle.Potions) then return "potion meta_prep 4"; end
    end
  end
  -- sigil_of_flame
  -- metamorphosis,if=cooldown.sigil_of_flame.charges>=1
  if S.SigilofFlame:IsCastable() and S.Metamorphosis:IsCastable() then
    if CastQueue(S.SigilofFlame, S.Metamorphosis) then return "sigil_of_flame and metamorphosis meta_prep 6"; end
  end
  -- metamorphosis,if=cooldown.sigil_of_flame.charges=0
  -- Note: Forced to main icon, as otherwise the main icon will be Pool.
  if S.Metamorphosis:IsCastable() and (S.SigilofFlame:Charges() == 0 or Player:PrevGCD(1, S.SigilofFlame)) then
    if Cast(S.Metamorphosis) then return "metamorphosis meta_prep 8"; end
  end
end

local function Metamorphosis()
  -- call_action_list,name=externals
  -- Note: Not handling externals.
  -- fel_desolation,if=buff.metamorphosis.remains<(gcd.max*3)
  if S.FelDesolation:IsReady() and (Player:BuffRemains(S.MetamorphosisBuff) < (Player:GCD() * 3)) then
    if Cast(S.FelDesolation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_desolation metamorphosis 2"; end
  end
  -- felblade,if=fury<50&(buff.metamorphosis.remains<(gcd.max*3))&cooldown.fel_desolation.up
  if S.Felblade:IsCastable() and (Player:Fury() < 50 and (Player:BuffRemains(S.MetamorphosisBuff) < (Player:GCD() * 3)) and S.FelDesolation:CooldownUp()) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade metamorphosis 4"; end
  end
  -- fracture,if=fury<50&!cooldown.felblade.up&(buff.metamorphosis.remains<(gcd.max*3))&cooldown.fel_desolation.up
  if S.Fracture:IsCastable() and (Player:Fury() < 50 and S.Felblade:CooldownDown() and (Player:BuffRemains(S.MetamorphosisBuff) < (Player:GCD() * 3)) and S.FelDesolation:CooldownUp()) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture metamorphosis 6"; end
  end
  -- sigil_of_doom,if=talent.illuminated_sigils&talent.cycle_of_binding&charges=max_charges
  -- Note: Using Charges check, as IsReady can return false due to very recent SigilofFlame usage.
  if S.SigilofDoom:Charges() > 0 and (S.IlluminatedSigils:IsAvailable() and S.CycleofBinding:IsAvailable() and S.SigilofDoom:Charges() >= S.SigilofDoom:MaxCharges()) then
    if Cast(S.SigilofDoom, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_doom metamorphosis 8"; end
  end
  -- immolation_aura
  if ImmoAbility:IsCastable() then
    if Cast(ImmoAbility, nil, nil, not IsInAoERange) then return "immolation_aura metamorphosis 8"; end
  end
  -- sigil_of_doom,if=!talent.student_of_suffering&(talent.ascending_flame|(!talent.ascending_flame&!prev_gcd.1.sigil_of_doom&(dot.sigil_of_doom.remains<(4-talent.quickened_sigils))))
  if S.SigilofDoom:IsReady() and (not S.StudentofSuffering:IsAvailable() and (S.AscendingFlame:IsAvailable() or (not S.AscendingFlame:IsAvailable() and not Player:PrevGCD(1, S.SigilofDoom) and (Target:DebuffRemains(S.SigilofDoomDebuff) < (4 - num(S.QuickenedSigils:IsAvailable())))))) then
    if Cast(S.SigilofDoom, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_doom metamorphosis 9"; end
  end
  -- sigil_of_doom,if=talent.student_of_suffering&!prev_gcd.1.sigil_of_flame&!prev_gcd.1.sigil_of_doom&(buff.student_of_suffering.remains<(4-talent.quickened_sigils))
  if S.SigilofDoom:IsReady() and (S.StudentofSuffering:IsAvailable() and not Player:PrevGCD(1, S.SigilofFlame) and not Player:PrevGCD(1, S.SigilofDoom) and (Player:BuffRemains(S.StudentofSufferingBuff) < (4 - num(S.QuickenedSigils:IsAvailable())))) then
    if Cast(S.SigilofDoom, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_doom metamorphosis 10"; end
  end
  -- sigil_of_doom,if=buff.metamorphosis.remains<((2-talent.quickened_sigils)+(charges*gcd.max))
  if S.SigilofDoom:IsReady() and (Player:BuffRemains(S.MetamorphosisBuff) < ((2 - num(S.QuickenedSigils:IsAvailable())) + (S.SigilofDoom:Charges() * Player:GCD()))) then
    if Cast(S.SigilofDoom, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_doom metamorphosis 11"; end
  end
  -- fel_desolation,if=soul_fragments<=3&(soul_fragments.inactive>=2|prev_gcd.1.sigil_of_spite)
  if S.FelDesolation:IsReady() and (SoulFragments <= 3 and (IncSoulFragments >= 2 or Player:PrevGCD(1, S.SigilofSpite))) then
    if Cast(S.FelDesolation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_desolation metamorphosis 10"; end
  end
  -- felblade,if=((cooldown.sigil_of_spite.remains<execute_time|cooldown.soul_carver.remains<execute_time)&cooldown.fel_desolation.remains<(execute_time+gcd.max)&fury<50)
  if S.Felblade:IsCastable() and ((S.SigilofSpite:CooldownRemains() < S.Felblade:ExecuteTime() or S.SoulCarver:CooldownRemains() < S.Felblade:ExecuteTime()) and S.FelDesolation:CooldownRemains() < (S.Felblade:ExecuteTime() + Player:GCD()) and Player:Fury() < 50) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade metamorphosis 14"; end
  end
  -- soul_carver,if=(!talent.spirit_bomb|(variable.single_target&!buff.demonsurge_spirit_burst.up))|(((soul_fragments.total+3)<=6)&fury>=40&!prev_gcd.1.sigil_of_spite)
  if S.SoulCarver:IsCastable() and (not S.SpiritBomb:IsAvailable() or (VarST and not Player:Demonsurge("SpiritBurst")) or ((TotalSoulFragments + 3) <= 6 and Player:Fury() >= 40 and not Player:PrevGCD(1, S.SigilofSpite))) then
    if Cast(S.SoulCarver, nil, nil, not IsInMeleeRange) then return "soul_carver metamorphosis 14"; end
  end
  -- sigil_of_spite,if=!talent.spirit_bomb|(fury>=80&(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total<=(2-talent.soul_sigils.rank)))|(soul_fragments.total<=2&buff.demonsurge_fel_desolation.up&fury>=50)
  if S.SigilofSpite:IsCastable() and (not S.SpiritBomb:IsAvailable() or (Player:Fury() >= 80 and (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments <= (2 - S.SoulSigils:TalentRank()))) or (TotalSoulFragments <= 2 and Player:Demonsurge("FelDesolation") and Player:Fury() >= 50)) then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite metamorphosis 16"; end
  end
  -- spirit_burst,if=variable.can_spburst&buff.demonsurge_spirit_burst.up
  if S.SpiritBurst:IsReady() and (VarCanSpBurst and Player:Demonsurge("SpiritBurst")) then
    if Cast(S.SpiritBurst, nil, nil, not IsInAoERange) then return "spirit_burst metamorphosis 18"; end
  end
  -- sigil_of_spite,if=soul_fragments.total<=(2-talent.soul_sigils.rank)
  if S.SigilofSpite:IsCastable() and (TotalSoulFragments <= (2 - S.SoulSigils:TalentRank())) then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite metamorphosis 22"; end
  end
  -- fel_desolation
  if S.FelDesolation:IsReady() then
    if Cast(S.FelDesolation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_desolation metamorphosis 24"; end
  end
  -- the_hunt
  if S.TheHunt:IsReady() then
    if Cast(S.TheHunt, nil, Settings.CommonsDS.DisplayStyle.TheHunt, not Target:IsInRange(50)) then return "the_hunt metamorphosis 25"; end
  end
  -- soul_sunder,if=buff.demonsurge_soul_sunder.up&!buff.demonsurge_spirit_burst.up&!variable.can_spburst_one_gcd
  if S.SoulSunder:IsReady() and (Player:Demonsurge("SoulSunder") and not Player:Demonsurge("SpiritBurst") and not VarCanSpBurstOneGCD) then
    if Cast(S.SoulSunder, nil, nil, not IsInMeleeRange) then return "soul_sunder metamorphosis 26"; end
  end
  -- spirit_burst,if=variable.can_spburst&(talent.fiery_demise&dot.fiery_brand.ticking|variable.big_aoe)&buff.metamorphosis.remains>(gcd.max*2)
  if S.SpiritBurst:IsReady() and (VarCanSpBurst and (S.FieryDemise:IsAvailable() and Target:DebuffUp(S.FieryBrandDebuff) or VarBigAoE) and Player:BuffRemains(S.MetamorphosisBuff) > (Player:GCD() * 2)) then
    if Cast(S.SpiritBurst, nil, nil, not IsInAoERange) then return "spirit_burst metamorphosis 28"; end
  end
  -- felblade,if=fury<40&(variable.can_spburst|variable.can_spburst_soon)&(buff.demonsurge_spirit_burst.up|talent.fiery_demise&dot.fiery_brand.ticking|variable.big_aoe)
  if S.Felblade:IsCastable() and (Player:Fury() < 40 and (VarCanSpBurst or VarCanSpBurstSoon) and (Player:Demonsurge("SpiritBurst") or (S.FieryDemise:IsAvailable() and Target:DebuffUp(S.FieryBrandDebuff) or VarBigAoE))) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade metamorphosis 30"; end
  end
  -- fracture,if=fury<40&(variable.can_spburst|variable.can_spburst_soon|variable.can_spburst_one_gcd)&(buff.demonsurge_spirit_burst.up|talent.fiery_demise&dot.fiery_brand.ticking|variable.big_aoe)
  if S.Fracture:IsCastable() and (Player:Fury() < 40 and (VarCanSpBurst or VarCanSpBurstSoon or VarCanSpBurstOneGCD) and (Player:Demonsurge("SpiritBurst") or (S.FieryDemise:IsAvailable() and Target:DebuffUp(S.FieryBrandDebuff) or VarBigAoE))) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture metamorphosis 32"; end
  end
  -- fracture,if=variable.can_spburst_one_gcd&(buff.demonsurge_spirit_burst.up|variable.big_aoe)&!prev_gcd.1.fracture
  if S.Fracture:IsCastable() and (VarCanSpBurstOneGCD and (Player:Demonsurge("SpiritBurst") or VarBigAoE) and not Player:PrevGCD(1, S.Fracture)) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture metamorphosis 34"; end
  end
  -- soul_sunder,if=variable.single_target&!variable.dont_soul_cleave
  if S.SoulSunder:IsReady() and (VarST and not VarDontSoulCleave) then
    if Cast(S.SoulSunder, nil, nil, not IsInMeleeRange) then return "soul_sunder metamorphosis 36"; end
  end
  -- spirit_burst,if=variable.can_spburst&buff.metamorphosis.remains>(gcd.max*2)
  if S.SpiritBurst:IsReady() and (VarCanSpBurst and Player:BuffRemains(S.MetamorphosisBuff) > (Player:GCD() * 2)) then
    if Cast(S.SpiritBurst, nil, nil, not IsInAoERange) then return "spirit_burst metamorphosis 38"; end
  end
  -- felblade,if=fury.deficit>=40
  if S.Felblade:IsCastable() and (Player:FuryDeficit() >= 40) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade metamorphosis 40"; end
  end
  -- soul_sunder,if=!variable.dont_soul_cleave&!(variable.big_aoe&(variable.can_spburst|variable.can_spburst_soon))
  if S.SoulSunder:IsReady() and (not VarDontSoulCleave and not (VarBigAoE and (VarCanSpBurst or VarCanSpBurstSoon))) then
    if Cast(S.SoulSunder, nil, nil, not IsInMeleeRange) then return "soul_sunder metamorphosis 42"; end
  end
  -- felblade
  if S.Felblade:IsCastable() then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade metamorphosis 38"; end
  end
  -- fracture,if=!prev_gcd.1.fracture
  if S.Fracture:IsCastable() and (not Player:PrevGCD(1, S.Fracture)) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture metamorphosis 44"; end
  end
  -- Manually added: shear
  if S.Shear:IsCastable() then
    if Cast(S.Shear, nil, nil, not IsInMeleeRange) then return "shear metamorphosis 42"; end
  end
end

local function FS()
  -- variable,name=crit_pct,op=set,value=(dot.sigil_of_flame.crit_pct+(talent.aura_of_pain*6))%100,if=active_dot.sigil_of_flame>0&talent.volatile_flameblood
  VarCritPct = 0
  if S.SigilofFlameDebuff:AuraActiveCount() > 0 and S.VolatileFlameblood:IsAvailable() then
    VarCritPct = (Player:CritChancePct() + (num(S.AuraofPain:IsAvailable()) * 6)) / 100
  end
  -- variable,name=fel_dev_sequence_time,op=set,value=2+(2*gcd.max)
  VarFelDevSequenceTime = 2 + (2 * Player:GCD())
  -- variable,name=fel_dev_sequence_time,op=add,value=gcd.max,if=talent.fiery_demise&cooldown.fiery_brand.up
  if S.FieryDemise:IsAvailable() and S.FieryBrand:CooldownUp() then
    VarFelDevSequenceTime = VarFelDevSequenceTime + Player:GCD()
  end
  -- variable,name=fel_dev_sequence_time,op=add,value=gcd.max,if=cooldown.sigil_of_flame.up|cooldown.sigil_of_flame.remains<variable.fel_dev_sequence_time
  if S.SigilofFlame:CooldownUp() or S.SigilofFlame:CooldownRemains() < VarFelDevSequenceTime then
    VarFelDevSequenceTime = VarFelDevSequenceTime + Player:GCD()
  end
  -- variable,name=fel_dev_sequence_time,op=add,value=gcd.max,if=cooldown.immolation_aura.up|cooldown.immolation_aura.remains<variable.fel_dev_sequence_time
  if ImmoAbility:CooldownUp() or ImmoAbility:CooldownRemains() < VarFelDevSequenceTime then
    VarFelDevSequenceTime = VarFelDevSequenceTime + Player:GCD()
  end
  -- variable,name=fel_dev_passive_fury_gen,op=set,value=0
  VarFelDevPassiveFuryGen = 0
  -- variable,name=fel_dev_passive_fury_gen,op=add,value=2.5*floor((buff.student_of_suffering.remains>?variable.fel_dev_sequence_time)),if=talent.student_of_suffering.enabled&(buff.student_of_suffering.remains>1|prev_gcd.1.sigil_of_flame)
  if S.StudentofSuffering:IsAvailable() and (Player:BuffRemains(S.StudentofSufferingBuff) > 1 or Player:PrevGCD(1, S.SigilofFlame)) then
    VarFelDevPassiveFuryGen = VarFelDevPassiveFuryGen + 2.5 * mathfloor(mathmin(Player:BuffRemains(S.StudentofSufferingBuff), VarFelDevSequenceTime))
  end
  -- variable,name=fel_dev_passive_fury_gen,op=add,value=30+(2*talent.flames_of_fury*spell_targets.sigil_of_flame),if=(cooldown.sigil_of_flame.remains<variable.fel_dev_sequence_time)
  if (S.SigilofFlame:CooldownRemains() < VarFelDevSequenceTime) then
    VarFelDevPassiveFuryGen = VarFelDevPassiveFuryGen + 30 + (2 * num(S.FlamesofFury:IsAvailable()) * EnemiesCount8yMelee)
  end
  -- variable,name=fel_dev_passive_fury_gen,op=add,value=8,if=cooldown.immolation_aura.remains<variable.fel_dev_sequence_time
  if ImmoAbility:CooldownRemains() < VarFelDevSequenceTime then
    VarFelDevPassiveFuryGen = VarFelDevPassiveFuryGen + 8
  end
  -- variable,name=fel_dev_passive_fury_gen,op=add,value=2*floor((buff.immolation_aura.remains>?variable.fel_dev_sequence_time)),if=buff.immolation_aura.remains>1
  if Player:BuffRemains(S.ImmolationAuraBuff) > 1 or Player:BuffRemains(S.ConsumingFireBuff) > 1 then
    local ImmoBuffRemains = Player:BuffUp(S.ConsumingFireBuff) and Player:BuffRemains(S.ConsumingFireBuff) or Player:BuffRemains(S.ImmolationAuraBuff)
    VarFelDevPassiveFuryGen = VarFelDevPassiveFuryGen + (2 * mathfloor(mathmin(ImmoBuffRemains, VarFelDevSequenceTime)))
  end
  -- variable,name=fel_dev_passive_fury_gen,op=add,value=7.5*variable.crit_pct*floor((buff.immolation_aura.remains>?variable.fel_dev_sequence_time)),if=talent.volatile_flameblood&buff.immolation_aura.remains>1
  if S.VolatileFlameblood:IsAvailable() and (Player:BuffRemains(S.ImmolationAuraBuff) > 1 or Player:BuffRemains(S.ConsumingFireBuff) > 1) then
    local ImmoBuffRemains = Player:BuffUp(S.ConsumingFireBuff) and Player:BuffRemains(S.ConsumingFireBuff) or Player:BuffRemains(S.ImmolationAuraBuff)
    VarFelDevPassiveFuryGen = VarFelDevPassiveFuryGen + (7.5 * VarCritPct * mathfloor(mathmin(ImmoBuffRemains, VarFelDevSequenceTime)))
  end
  -- variable,name=fel_dev_passive_fury_gen,op=add,value=22,if=talent.darkglare_boon.enabled
  if S.DarkglareBoon:IsAvailable() then
    VarFelDevPassiveFuryGen = VarFelDevPassiveFuryGen + 22
  end
  -- variable,name=spbomb_threshold,op=setif,condition=talent.fiery_demise&dot.fiery_brand.ticking,value=(variable.single_target*5)+(variable.small_aoe*4)+(variable.big_aoe*4),value_else=(variable.single_target*5)+(variable.small_aoe*4)+(variable.big_aoe*4)
  -- Note: value and value_else are the same currently.
  --if S.FieryDemise:IsAvailable() and S.FieryBrandDebuff:AuraActiveCount() > 0 then
    VarSpBombThreshold = (num(VarST) * 5) + (num(VarSmallAoE) * 5) + (num(VarBigAoE) * 4)
  --else
    --VarSpBombThreshold = (num(VarST) * 5) + (num(VarSmallAoE) * 4) + (num(VarBigAoE) * 4)
  --end
  -- variable,name=can_spbomb,op=setif,condition=talent.spirit_bomb,value=soul_fragments>=variable.spbomb_threshold,value_else=0
  VarCanSpBomb = S.SpiritBomb:IsAvailable() and SoulFragments >= VarSpBombThreshold
  -- variable,name=can_spbomb_soon,op=setif,condition=talent.spirit_bomb,value=soul_fragments.total>=variable.spbomb_threshold,value_else=0
  VarCanSpBombSoon = S.SpiritBomb:IsAvailable() and TotalSoulFragments >= VarSpBombThreshold
  -- variable,name=can_spbomb_one_gcd,op=setif,condition=talent.spirit_bomb,value=(soul_fragments.total+variable.num_spawnable_souls)>=variable.spbomb_threshold,value_else=0
  VarCanSpBombOneGCD = S.SpiritBomb:IsAvailable() and (TotalSoulFragments + VarNumSpawnableSouls) >= VarSpBombThreshold
  -- variable,name=spburst_threshold,op=setif,condition=talent.fiery_demise&dot.fiery_brand.ticking,value=(variable.single_target*5)+(variable.small_aoe*5)+(variable.big_aoe*4),value_else=(variable.single_target*5)+(variable.small_aoe*5)+(variable.big_aoe*4)
  -- Note: value and value_else are the same currently.
  --if S.FieryDemise:IsAvailable() and S.FieryBrandDebuff:AuraActiveCount() > 0 then
    VarSpBurstThreshold = (num(VarST) * 5) + (num(VarSmallAoE) * 5) + (num(VarBigAoE) * 4)
  --else
    --VarSpBurstThreshold = (num(VarST) * 5) + (num(VarSmallAoE) * 4) + (num(VarBigAoE) * 4)
  --end
  -- variable,name=can_spburst,op=setif,condition=talent.spirit_bomb,value=soul_fragments>=variable.spburst_threshold,value_else=0
  VarCanSpBurst = S.SpiritBomb:IsAvailable() and SoulFragments >= VarSpBurstThreshold
  -- variable,name=can_spburst_soon,op=setif,condition=talent.spirit_bomb,value=soul_fragments.total>=variable.spburst_threshold,value_else=0
  VarCanSpBurstSoon = S.SpiritBomb:IsAvailable() and TotalSoulFragments >= VarSpBurstThreshold
  -- variable,name=can_spburst_one_gcd,op=setif,condition=talent.spirit_bomb,value=(soul_fragments.total+variable.num_spawnable_souls)>=variable.spburst_threshold,value_else=0
  VarCanSpBurstOneGCD = S.SpiritBomb:IsAvailable() and (TotalSoulFragments + VarNumSpawnableSouls) >= VarSpBurstThreshold
  -- variable,name=meta_prep_time,op=set,value=0
  VarMetaPrepTime = 0
  -- variable,name=meta_prep_time,op=add,value=action.fiery_brand.execute_time,if=talent.fiery_demise&cooldown.fiery_brand.up
  if S.FieryDemise:IsAvailable() and S.FieryBrand:CooldownUp() then
    VarMetaPrepTime = S.FieryBrand:ExecuteTime()
  end
  -- variable,name=meta_prep_time,op=add,value=action.sigil_of_flame.execute_time*action.sigil_of_flame.charges
  VarMetaPrepTime = VarMetaPrepTime + (S.SigilofFlame:ExecuteTime() * S.SigilofFlame:Charges())
  -- variable,name=dont_soul_cleave,op=setif,condition=buff.metamorphosis.up&buff.demonsurge_hardcast.up,
  if Player:BuffUp(S.MetamorphosisBuff) and Player:Demonsurge("Hardcast") then
    -- value=buff.demonsurge_spirit_burst.up|(buff.metamorphosis.remains<(gcd.max*2)&(!((fury+variable.fel_dev_passive_fury_gen)>=120)|!(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4))),
    VarDontSoulCleave = Player:Demonsurge("SpiritBurst") or (Player:BuffRemains(S.MetamorphosisBuff) < (Player:GCD() * 2) and (not ((Player:Fury() + VarFelDevPassiveFuryGen) >= 120) or not (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments >= 4)))
  else
    -- value_else=(cooldown.fel_devastation.remains<(gcd.max*3)&(!((fury+variable.fel_dev_passive_fury_gen)>=120)|!(variable.can_spburst|variable.can_spburst_soon|soul_fragments.total>=4)))
    VarDontSoulCleave = (S.FelDevastation:CooldownRemains() < (Player:GCD() * 3) and (not ((Player:Fury() + VarFelDevPassiveFuryGen) >= 120) or not (VarCanSpBurst or VarCanSpBurstSoon or TotalSoulFragments >= 4)))
  end
  -- variable,name=fiery_brand_back_before_meta,op=setif,condition=talent.down_in_flames,value=charges>=max_charges|(charges_fractional>=1&cooldown.fiery_brand.full_recharge_time<=gcd.remains+execute_time)|(charges_fractional>=1&((1-(charges_fractional-1))*cooldown.fiery_brand.duration)<=cooldown.metamorphosis.remains),value_else=cooldown.fiery_brand.duration<=cooldown.metamorphosis.remains
  if S.DowninFlames:IsAvailable() then
    VarFBBeforeMeta = S.FieryBrand:Charges() >= S.FieryBrand:MaxCharges() or (S.FieryBrand:ChargesFractional() >= 1 and S.FieryBrand:FullRecharge() <= Player:GCDRemains() + S.FieryBrand:ExecuteTime()) or (S.FieryBrand:ChargesFractional() >= 1 and ((1 - (S.FieryBrand:ChargesFractional() - 1)) * VarFieryBrandCD) <= S.Metamorphosis:CooldownRemains())
  else
    VarFBBeforeMeta = VarFieryBrandCD <= S.Metamorphosis:CooldownRemains()
  end

  -- variable,name=hold_sof_for_meta,op=setif,condition=talent.illuminated_sigils,
  if S.IlluminatedSigils:IsAvailable() then
    -- value=(charges_fractional>=1&((1-(charges_fractional-1))*cooldown.sigil_of_flame.duration)>cooldown.metamorphosis.remains),
    VarHoldSoFForMeta = S.SigilofFlame:ChargesFractional() >= 1 and ((1 - (S.SigilofFlame:ChargesFractional() - 1)) * VarSoFCD) > S.Metamorphosis:CooldownRemains()
  else
    -- value_else=cooldown.sigil_of_flame.duration>cooldown.metamorphosis.remains
    VarHoldSoFForMeta = VarSoFCD > S.Metamorphosis:CooldownRemains()
  end

-- variable,name=hold_sof_for_fel_dev,op=setif,condition=talent.illuminated_sigils,
  if S.IlluminatedSigils:IsAvailable() then
    -- value=(charges_fractional>=1&((1-(charges_fractional-1))*cooldown.sigil_of_flame.duration)>cooldown.fel_devastation.remains),
    VarHoldSoFForFelDev = S.SigilofFlame:ChargesFractional() >= 1 and ((1 - (S.SigilofFlame:ChargesFractional() - 1)) * VarSoFCD) > S.FelDevastation:CooldownRemains()
  else
    -- value_else=cooldown.sigil_of_flame.duration>cooldown.fel_devastation.remains
    VarHoldSoFForFelDev = VarSoFCD > S.FelDevastation:CooldownRemains()
  end

  -- variable,name=hold_sof_for_student,op=setif,condition=talent.student_of_suffering,
  if S.StudentofSuffering:IsAvailable() then
    -- value=prev_gcd.1.sigil_of_flame|(buff.student_of_suffering.remains>(4-talent.quickened_sigils)),
    VarHoldSoFForStudent = Player:PrevGCD(1, S.SigilofFlame) or Player:BuffRemains(S.StudentofSufferingBuff) > (4 - num(S.QuickenedSigils:IsAvailable()))
  else
    -- value_else=0
    VarHoldSoFForStudent = 0
  end

  -- variable,name=hold_sof_for_dot,op=setif,condition=talent.ascending_flame,
  if S.AscendingFlame:IsAvailable() then
    -- value=0,
    VarHoldSoFForDot = 0
  else
    -- value_else=prev_gcd.1.sigil_of_flame|(dot.sigil_of_flame.remains>(4-talent.quickened_sigils))
    VarHoldSoFForDot = Player:PrevGCD(1, S.SigilofFlame) or Target:DebuffRemains(S.SigilofFlameDebuff) > (4 - num(S.QuickenedSigils:IsAvailable()))
  end

  -- variable,name=hold_sof_for_precombat,value=(talent.illuminated_sigils&time<(2-talent.quickened_sigils))
  -- Note (Jom): Added an extra second (2sec->3sec) to the timing here to account for any hiccups in determing if precombat has ended. Important not to double-cast SoF.
  VarHoldSoFForPrecombat = S.IlluminatedSigils:IsAvailable() and HL.CombatTime() < (3 - num(S.QuickenedSigils:IsAvailable()))

  -- use_items,use_off_gcd=1,if=!buff.metamorphosis.up
  if (Settings.Commons.Enabled.Trinkets or Settings.Commons.Enabled.Items) and Player:BuffDown(S.MetamorphosisBuff) then
    local ItemToUse, ItemSlot, ItemRange = Player:GetUseableItems(OnUseExcludes)
    if ItemToUse then
      local DisplayStyle = Settings.CommonsDS.DisplayStyle.Trinkets
      if ItemSlot ~= 13 and ItemSlot ~= 14 then DisplayStyle = Settings.CommonsDS.DisplayStyle.Items end
      if ((ItemSlot == 13 or (ItemSlot == 14 and false)) and Settings.Commons.Enabled.Trinkets) or (ItemSlot ~= 13 and ItemSlot ~= 14 and Settings.Commons.Enabled.Items) then
        if Cast(ItemToUse, nil, DisplayStyle, not Target:IsInRange(ItemRange)) then return "Generic use_items for " .. ItemToUse:Name(); end
      end
    end
  end

  if (Settings.Vengeance.UseSimplifiedRotation) then
    return SimplifiedAPL()
  end

  -- immolation_aura,if=time<4
  if ImmoAbility:IsCastable() and (HL.CombatTime() < 4) then
    if Cast(ImmoAbility) then return "immolation_aura fs 1"; end
  end
  -- immolation_aura,if=!(cooldown.metamorphosis.up&prev_gcd.1.sigil_of_flame)&!(talent.fallout&talent.spirit_bomb&spell_targets.spirit_bomb>=3&((buff.metamorphosis.up&(variable.can_spburst|variable.can_spburst_soon))|(!buff.metamorphosis.up&(variable.can_spbomb|variable.can_spbomb_soon))))&!(buff.metamorphosis.up&buff.demonsurge_hardcast.up)
  if ImmoAbility:IsCastable() and (not (S.Metamorphosis:CooldownUp() and Player:PrevGCD(1, S.SigilofFlame)) and not (S.Fallout:IsAvailable() and S.SpiritBomb:IsAvailable() and EnemiesCount8yMelee >= 3 and (Player:BuffUp(S.MetamorphosisBuff) and (VarCanSpBurst or VarCanSpBurstSoon)) or (not Player:BuffUp(S.MetamorphosisBuff) and (VarCanSpBomb or VarCanSpBombSoon)))) and not (Player:BuffUp(S.MetamorphosisBuff) and Player:Demonsurge("Hardcast")) then
    if Cast(ImmoAbility) then return "immolation_aura fs 2"; end
  end

  -- sigil_of_flame,if=!talent.student_of_suffering&!variable.hold_sof_for_dot&!variable.hold_sof_for_precombat
  if S.SigilofFlame:IsCastable() and (not S.StudentofSuffering:IsAvailable() and not VarHoldSoFForDot and not VarHoldSoFForPrecombat) then
    if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame fs 3"; end
  end

  -- sigil_of_flame,if=!variable.hold_sof_for_precombat&(charges=max_charges|(!variable.hold_sof_for_student&!variable.hold_sof_for_dot&!variable.hold_sof_for_meta&!variable.hold_sof_for_fel_dev))
  if S.SigilofFlame:IsCastable() and (not VarHoldSoFForPrecombat and (S.SigilofFlame:Charges() == S.SigilofFlame:MaxCharges() or (not VarHoldSoFForStudent and not VarHoldSoFForDot and not VarHoldSoFForMeta and not VarHoldSoFForFelDev))) then
    if Cast(S.SigilofFlame, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_flame fs 4"; end
  end
  -- fiery_brand,if=active_dot.fiery_brand=0&(!talent.fiery_demise|((talent.down_in_flames&charges>=max_charges)|variable.fiery_brand_back_before_meta))
  if S.FieryBrand:IsCastable() and (S.FieryBrandDebuff:AuraActiveCount() == 0 and (not S.FieryDemise:IsAvailable() or (S.DowninFlames:IsAvailable() and S.FieryBrand:Charges() >= S.FieryBrand:MaxCharges()) or VarFBBeforeMeta)) then
    if Cast(S.FieryBrand, nil, Settings.Vengeance.DisplayStyle.FieryBrand, not Target:IsSpellInRange(S.FieryBrand)) then return "fiery_brand fs 5"; end
  end
  -- call_action_list,name=fs_execute,if=fight_remains<20
  if BossFightRemains < 20 then
    local ShouldReturn = FSExecute(); if ShouldReturn then return ShouldReturn; end
  end
    -- run_action_list,name=metamorphosis,if=buff.metamorphosis.up&buff.demonsurge_hardcast.up
  if Player:BuffUp(S.MetamorphosisBuff) and Player:Demonsurge("Hardcast") then
    local ShouldReturn = Metamorphosis(); if ShouldReturn then return ShouldReturn; end
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for Metamorphosis()"; end
  end
  -- run_action_list,name=fel_dev,if=buff.metamorphosis.up&!buff.demonsurge_hardcast.up&!buff.metamorphosis.duration>=8&(buff.demonsurge_soul_sunder.up|buff.demonsurge_spirit_burst.up)
  if Player:BuffUp(S.MetamorphosisBuff) and not Player:Demonsurge("Hardcast") and Player:BuffRemains(S.MetamorphosisBuff) < 8 and (Player:Demonsurge("SoulSunder") or Player:Demonsurge("SpiritBurst")) then
    local ShouldReturn = FelDev(); if ShouldReturn then return ShouldReturn; end
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for FelDev()"; end
  end
  -- run_action_list,name=fel_dev_prep,if=!buff.demonsurge_hardcast.up&(cooldown.fel_devastation.up|(cooldown.fel_devastation.remains<=(gcd.max*3)))
  if not Player:Demonsurge("Hardcast") and (S.FelDevastation:CooldownUp() or (S.FelDevastation:CooldownRemains() <= (Player:GCD() * 3))) then
    local ShouldReturn = FelDevPrep(); if ShouldReturn then return ShouldReturn; end
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for FelDevPrep()"; end
  end
  -- run_action_list,name=meta_prep,if=(cooldown.metamorphosis.remains<=variable.meta_prep_time)&!cooldown.fel_devastation.up&!cooldown.fel_devastation.remains<10&!buff.demonsurge_soul_sunder.up&!buff.demonsurge_spirit_burst.up
  if (S.Metamorphosis:CooldownRemains() <= VarMetaPrepTime) and S.FelDevastation:CooldownDown() and S.FelDevastation:CooldownRemains() >= 10 and not Player:Demonsurge("SoulSunder") and not Player:Demonsurge("SpiritBurst") then
    local ShouldReturn = MetaPrep(); if ShouldReturn then return ShouldReturn; end
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for MetaPrep()"; end
  end
  -- the_hunt
  if S.TheHunt:IsCastable() then
    if Cast(S.TheHunt, nil, Settings.CommonsDS.DisplayStyle.TheHunt, not Target:IsInRange(50)) then return "the_hunt fs 8"; end
  end
  -- felblade,if=((cooldown.sigil_of_spite.remains<execute_time|cooldown.soul_carver.remains<execute_time)&cooldown.fel_devastation.remains<(execute_time+gcd.max)&fury<50)
  if S.Felblade:IsCastable() and ((S.SigilofSpite:CooldownRemains() < S.Felblade:ExecuteTime() or S.SoulCarver:CooldownRemains() < S.Felblade:ExecuteTime()) and S.FelDevastation:CooldownRemains() < (S.Felblade:ExecuteTime() + Player:GCD()) and Player:Fury() < 50) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade fs 10"; end
  end
  -- soul_carver,if=(!talent.fiery_demise|talent.fiery_demise&dot.fiery_brand.ticking)&((!talent.spirit_bomb|variable.single_target)|(talent.spirit_bomb&!prev_gcd.1.sigil_of_spite&((soul_fragments.total+3<=5&fury>=40)|(soul_fragments.total=0&fury>=15))))
  if S.SoulCarver:IsCastable() and ((not S.FieryDemise:IsAvailable() or S.FieryDemise:IsAvailable() and S.FieryBrandDebuff:AuraActiveCount() > 0) and ((not S.SpiritBomb:IsAvailable() or VarST) or (S.SpiritBomb:IsAvailable() and not Player:PrevGCD(1, S.SigilofSpite) and ((TotalSoulFragments == 0 and Player:Fury() >= 40) or (TotalSoulFragments + 3 <= 4 and Player:Fury() >= 15))))) then
    if Cast(S.SoulCarver, nil, nil, not IsInMeleeRange) then return "soul_carver fs 12"; end
  end
  -- sigil_of_spite,if=(!talent.spirit_bomb|variable.single_target)|cooldown.fel_devastation.remains>(gcd.max*3)&((fury>=75&talent.spirit_bomb&(variable.can_spbomb|variable.can_spbomb_soon|(buff.metamorphosis.up&(variable.can_spburst|variable.can_spburst_soon))))|soul_fragments<=1)
  if S.SigilofSpite:IsCastable() and ((not S.SpiritBomb:IsAvailable() or VarST) or S.FelDevastation:CooldownRemains() > (Player:GCD() * 3) and ((Player:Fury() >= 75 and S.SpiritBomb:IsAvailable() and (VarCanSpBomb or VarCanSpBombSoon or (Player:BuffUp(S.MetamorphosisBuff) and (VarCanSpBurst or VarCanSpBurstSoon)))) or SoulFragments <= 1)) then
    if Cast(S.SigilofSpite, nil, Settings.CommonsDS.DisplayStyle.Sigils, not Target:IsInRange(30)) then return "sigil_of_spite fs 14"; end
  end
  -- spirit_burst,if=variable.can_spburst&talent.fiery_demise&dot.fiery_brand.ticking&!(cooldown.fel_devastation.remains<(gcd.max*3))
  if S.SpiritBurst:IsReady() and (VarCanSpBurst and S.FieryDemise:IsAvailable() and S.FieryBrandDebuff:AuraActiveCount() > 0 and not (S.FelDevastation:CooldownRemains() < (Player:GCD() * 3))) then
    if Cast(S.SpiritBurst, nil, nil, not IsInAoERange) then return "spirit_burst fs 16"; end
  end
  -- spirit_bomb,if=variable.can_spbomb&talent.fiery_demise&dot.fiery_brand.ticking&!(cooldown.fel_devastation.remains<(gcd.max*3))
  if S.SpiritBomb:IsReady() and (VarCanSpBomb and S.FieryDemise:IsAvailable() and S.FieryBrandDebuff:AuraActiveCount() > 0 and not (S.FelDevastation:CooldownRemains() < (Player:GCD() * 3))) then
    if Cast(S.SpiritBurst, nil, nil, not IsInAoERange) then return "spirit_bomb fs 18"; end
  end
  -- soul_sunder,if=variable.single_target&!variable.dont_soul_cleave
  if S.SoulSunder:IsReady() and (VarST and not VarDontSoulCleave) then
    if Cast(S.SoulSunder, nil, nil, not IsInMeleeRange) then return "soul_sunder fs 16"; end
  end
  -- soul_cleave,if=variable.single_target&!variable.dont_soul_cleave
  if S.SoulCleave:IsReady() and (VarST and not VarDontSoulCleave) then
    if Cast(S.SoulCleave, nil, nil, not IsInMeleeRange) then return "soul_cleave fs 18"; end
  end
  -- Manually added: wait,if=!variable.can_spburst&soul_fragments.total>=variable.spburst_threshold
  if S.SpiritBurst:IsReady() and not VarCanSpBurst and TotalSoulFragments >= VarSpBurstThreshold and SoulFragments < 5 then
    if CastAnnotated(S.Pool, false, "WAIT") then return "Wait for Soul Fragments (Spirit Burst)"; end
  end
  -- spirit_burst,if=variable.can_spburst&!cooldown.fel_devastation.remains<(gcd.max*3)
  if S.SpiritBurst:IsReady() and (VarCanSpBurst and not (S.FelDevastation:CooldownRemains() < (Player:GCD() * 3))) then
    if Cast(S.SpiritBurst, nil, nil, not IsInAoERange) then return "spirit_burst fs 20"; end
  end
  -- Manually added: wait,if=!variable.can_spb&soul_fragments.total>=variable.spbomb_threshold
  if not VarCanSpB and TotalSoulFragments >= VarSpBombThreshold and SoulFragments < 5 then
    if CastAnnotated(S.Pool, false, "WAIT") then return "Wait for Soul Fragments (Spirit Bomb)"; end
  end
  -- spirit_bomb,if=variable.can_spbomb&!cooldown.fel_devastation.remains<(gcd.max*3)
  if S.SpiritBomb:IsReady() and (VarCanSpBomb and not (S.FelDevastation:CooldownRemains() < (Player:GCD() * 3))) then
    if Cast(S.SpiritBomb, nil, nil, not Target:IsInMeleeRange(8)) then return "spirit_bomb fs 22"; end
  end
  -- felblade,if=((fury<40&((buff.metamorphosis.up&(variable.can_spburst|variable.can_spburst_soon))|(!buff.metamorphosis.up&(variable.can_spbomb|variable.can_spbomb_soon)))))
  if S.Felblade:IsCastable() and (Player:Fury() < 40 and ((Player:BuffUp(S.MetamorphosisBuff) and (VarCanSpBurst or VarCanSpBurstSoon)) or (Player:BuffDown(S.MetamorphosisBuff) and (VarCanSpBomb or VarCanSpBombSoon)))) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade fs 28"; end
  end
  -- fracture,if=((fury<40&((buff.metamorphosis.up&(variable.can_spburst|variable.can_spburst_soon))|(!buff.metamorphosis.up&(variable.can_spbomb|variable.can_spbomb_soon))))|(buff.metamorphosis.up&variable.can_spburst_one_gcd)|(!buff.metamorphosis.up&variable.can_spbomb_one_gcd))
  if S.Fracture:IsCastable() and ((Player:Fury() < 40 and ((Player:BuffUp(S.MetamorphosisBuff) and (VarCanSpBurst or VarCanSpBurstSoon)) or (Player:BuffDown(S.MetamorphosisBuff) and (VarCanSpBomb or VarCanSpBombSoon)))) or (Player:BuffUp(S.MetamorphosisBuff) and VarCanSpBurstOneGCD) or (Player:BuffDown(S.MetamorphosisBuff) and VarCanSpBombOneGCD)) then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture fs 30"; end
  end
  -- felblade,if=fury.deficit>=40
  if S.Felblade:IsCastable() and (Player:FuryDeficit() >= 40) then
    if Cast(S.Felblade, nil, nil, not Target:IsSpellInRange(S.Felblade)) then return "felblade fs 36"; end
  end
  -- soul_sunder,if=!variable.dont_soul_cleave
  -- soul_cleave,if=!variable.dont_soul_cleave
  if not VarDontSoulCleave then
    if S.SoulSunder:IsReady() then
      if Cast(S.SoulSunder, nil, nil, not IsInMeleeRange) then return "soul_sunder fs 32"; end
    end
    if S.SoulCleave:IsReady() then
      if Cast(S.SoulCleave, nil, nil, not IsInMeleeRange) then return "soul_cleave fs 34"; end
    end
  end
  -- fracture
  if S.Fracture:IsCastable() then
    if Cast(S.Fracture, nil, nil, not IsInMeleeRange) then return "fracture fs 38"; end
  end
  -- Manually added: shear
  if S.Shear:IsCastable() then
    if Cast(S.Shear, nil, nil, not IsInMeleeRange) then return "shear fs 40"; end
  end
  -- throw_glaive
  if S.ThrowGlaive:IsCastable() then
    if Cast(S.ThrowGlaive, nil, nil, not Target:IsSpellInRange(S.ThrowGlaive)) then return "throw_glaive fs 42"; end
  end
end

--- ===== APL Main =====
local function APL()
  Enemies8yMelee = Player:GetEnemiesInMeleeRange(8)
  if (AoEON()) then
    EnemiesCount8yMelee = #Enemies8yMelee
  else
    EnemiesCount8yMelee = 1
  end

  if Everyone.TargetIsValid() or Player:AffectingCombat() then
    -- Calculate fight_remains
    BossFightRemains = HL.BossFightRemains()
    FightRemains = BossFightRemains
    if FightRemains == 11111 then
      FightRemains = HL.FightRemains(Enemies8yMelee, false)
    end

    -- Update Soul Fragment Totals
    --UpdateSoulFragments()
    SoulFragments = DemonHunter.Souls.AuraSouls
    IncSoulFragments = DemonHunter.Souls.IncomingSouls
    TotalSoulFragments = SoulFragments + IncSoulFragments

    -- Update if target is in melee range
    UpdateIsInMeleeRange()

    -- Set Tanking Variables
    ActiveMitigationNeeded = Player:ActiveMitigationNeeded()
    IsTanking = Player:IsTankingAoE(8) or Player:IsTanking(Target)

    -- Variables from Precombat
    -- variable,name=single_target,value=spell_targets.spirit_bomb=1
    VarST = EnemiesCount8yMelee == 1
    -- variable,name=small_aoe,value=spell_targets.spirit_bomb>=2&spell_targets.spirit_bomb<=5
    VarSmallAoE = EnemiesCount8yMelee >= 2 and EnemiesCount8yMelee <= 5
    -- variable,name=big_aoe,value=spell_targets.spirit_bomb>=6
    VarBigAoE = EnemiesCount8yMelee >= 6

    -- ImmolationAura or ConsumingFire?
    ImmoAbility = S.ConsumingFire:IsLearned() and S.ConsumingFire or S.ImmolationAura
  end

  if Everyone.TargetIsValid() then
    -- Precombat
    if not Player:AffectingCombat() then
      local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
    end
    -- variable,name=num_spawnable_souls,op=reset,default=0
    VarNumSpawnableSouls = 0
    -- variable,name=num_spawnable_souls,op=max,value=1,if=talent.soul_sigils&cooldown.sigil_of_flame.up
    if S.SoulSigils:IsAvailable() and S.SigilofFlame:CooldownUp() then
      VarNumSpawnableSouls = mathmax(VarNumSpawnableSouls, 1)
    end
    -- variable,name=num_spawnable_souls,op=max,value=2,if=talent.fracture&cooldown.fracture.charges_fractional>=1&!buff.metamorphosis.up
    if S.Fracture:IsAvailable() and S.Fracture:ChargesFractional() >= 1 and Player:BuffDown(S.MetamorphosisBuff) then
      VarNumSpawnableSouls = 2
    end
    -- variable,name=num_spawnable_souls,op=max,value=3,if=talent.fracture&cooldown.fracture.charges_fractional>=1&buff.metamorphosis.up
    if S.Fracture:IsAvailable() and S.Fracture:ChargesFractional() >= 1 and Player:BuffUp(S.MetamorphosisBuff) then
      VarNumSpawnableSouls = 3
    end
    -- variable,name=num_spawnable_souls,op=add,value=1,if=talent.soul_carver&(cooldown.soul_carver.remains>(cooldown.soul_carver.duration-3))
    if S.SoulCarver:IsAvailable() and S.SoulCarver:CooldownRemains() > 57 then
      VarNumSpawnableSouls = VarNumSpawnableSouls + 1
    end
    -- auto_attack
    -- disrupt,if=target.debuff.casting.react (Interrupts)
    local ShouldReturn = Everyone.Interrupt(S.Disrupt, Settings.CommonsDS.DisplayStyle.Interrupts); if ShouldReturn then return ShouldReturn; end
    -- Manually added: Defensives
    if (IsTanking) then
      local ShouldReturn = Defensives(); if ShouldReturn then return ShouldReturn; end
    end
    -- infernal_strike,use_off_gcd=1
    --if S.InfernalStrike:IsCastable() and (not Settings.Vengeance.ConserveInfernalStrike or S.InfernalStrike:ChargesFractional() > 1.9) and (S.InfernalStrike:TimeSinceLastCast() > 2) then
      --if Cast(S.InfernalStrike, Settings.Vengeance.OffGCDasOffGCD.InfernalStrike, nil, not Target:IsInRange(30)) then return "infernal_strike main 2"; end
    --end
    -- demon_spikes,use_off_gcd=1,if=!buff.demon_spikes.up&!cooldown.pause_action.remains
    -- Note: Handled via Defensives()
    -- run_action_list,name=ar,if=hero_tree.aldrachi_reaver
    if Player:HeroTreeID() == 35 then
      local ShouldReturn = AR(); if ShouldReturn then return ShouldReturn; end
      if CastAnnotated(S.Pool, false, "WAIT") then return "Wait for AR()"; end
    end
    -- run_action_list,name=fs,if=hero_tree.felscarred
    if Player:HeroTreeID() == 34 then
      local ShouldReturn = FS(); if ShouldReturn then return ShouldReturn; end
      if CastAnnotated(S.Pool, false, "WAIT") then return "Wait for FS()"; end
    end
    -- Manually added: run_action_list,name=ar,if=!hero_tree.aldrachi_reaver&!hero_tree.felscarred
    -- Note: This is just to handle sub-level 71 players. Might find a better way to optimize this?
    if Player:HeroTreeID() ~= 34 and Player:HeroTreeID() ~= 35 then
      if S.FelDevastation:IsReady() then
        if Cast(S.FelDevastation, Settings.Vengeance.GCDasOffGCD.FelDevastation, nil, not Target:IsInMeleeRange(20)) then return "fel_devastation low_level 2"; end
      end
      local ShouldReturn = AR(); if ShouldReturn then return ShouldReturn; end
      if CastAnnotated(S.Pool, false, "WAIT") then return "Wait for AR() (Low Level)"; end
    end
    -- If nothing else to do, show the Pool icon
    if CastAnnotated(S.Pool, false, "WAIT") then return "Wait/Pool Resources"; end
  end
end

local function Init()
  S.FieryBrandDebuff:RegisterAuraTracking()
  S.SigilofFlameDebuff:RegisterAuraTracking()

  HR.Print("Vengeance Demon Hunter rotation has been updated for patch 11.0.2.")
end

HR.SetAPL(581, APL, Init)
